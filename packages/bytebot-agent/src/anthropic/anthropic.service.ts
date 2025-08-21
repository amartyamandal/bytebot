import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Anthropic, { APIUserAbortError } from '@anthropic-ai/sdk';
import {
  MessageContentBlock,
  MessageContentType,
  TextContentBlock,
  ToolUseContentBlock,
  ThinkingContentBlock,
  RedactedThinkingContentBlock,
  isUserActionContentBlock,
  isComputerToolUseContentBlock,
} from '@bytebot/shared';
import { DEFAULT_MODEL } from './anthropic.constants';
import { Message, Role } from '@prisma/client';
import { anthropicTools } from './anthropic.tools';
import {
  BytebotAgentService,
  BytebotAgentInterrupt,
  BytebotAgentResponse,
} from '../agent/agent.types';

@Injectable()
export class AnthropicService implements BytebotAgentService {
  private readonly anthropic: Anthropic;
  private readonly logger = new Logger(AnthropicService.name);
  private readonly maxRetries: number;
  private readonly baseRetryDelayMs: number;

  constructor(private readonly configService: ConfigService) {
    const apiKey = this.configService.get<string>('ANTHROPIC_API_KEY');
    this.maxRetries = Number(
      this.configService.get<string>('ANTHROPIC_MAX_RETRIES') ?? '5',
    );
    this.baseRetryDelayMs = Number(
      this.configService.get<string>('ANTHROPIC_RETRY_BASE_MS') ?? '500',
    );

    if (!apiKey) {
      this.logger.warn(
        'ANTHROPIC_API_KEY is not set. AnthropicService will not work properly.',
      );
    }

    this.anthropic = new Anthropic({
      apiKey: apiKey || 'dummy-key-for-initialization',
    });
  }

  async generateMessage(
    systemPrompt: string,
    messages: Message[],
    model: string = DEFAULT_MODEL.name,
    useTools: boolean = true,
    signal?: AbortSignal,
  ): Promise<BytebotAgentResponse> {
    try {
      const maxTokens = 8192;

      // Convert our message content blocks to Anthropic's expected format
      const anthropicMessages = this.formatMessagesForAnthropic(messages);

      // add cache_control to last tool
      anthropicTools[anthropicTools.length - 1].cache_control = {
        type: 'ephemeral',
      };

      // Make the API call with retry for transient errors (e.g. 529 overloaded)
      const response = await this.executeWithRetry(
        async () =>
          this.anthropic.messages.create(
            {
              model,
              max_tokens: maxTokens * 2,
              thinking: { type: 'disabled' },
              system: [
                {
                  type: 'text',
                  text: systemPrompt,
                  cache_control: { type: 'ephemeral' },
                },
              ],
              messages: anthropicMessages,
              tools: useTools ? anthropicTools : [],
            },
            { signal },
          ),
        'messages.create',
      );

      // Convert Anthropic's response to our message content blocks format
      return {
        contentBlocks: this.formatAnthropicResponse(response.content),
        tokenUsage: {
          inputTokens: response.usage.input_tokens,
          outputTokens: response.usage.output_tokens,
          totalTokens:
            response.usage.input_tokens + response.usage.output_tokens,
        },
      };
    } catch (error) {
      this.logger.log(error);

      if (error instanceof APIUserAbortError) {
        this.logger.log('Anthropic API call aborted');
        throw new BytebotAgentInterrupt();
      }
      this.logger.error(
        `Error sending message to Anthropic: ${error.message}`,
        error.stack,
      );
      throw error;
    }
  }

  /**
   * Generic retry helper with exponential backoff + jitter for transient Anthropic errors.
   * Retries on: HTTP/SDK status 408/429/500/502/503/504/529, anthropic overloaded_error / rate_limit_error.
   */
  private async executeWithRetry<T>(
    fn: () => Promise<T>,
    context: string,
  ): Promise<T> {
    let attempt = 0;
    let lastError: any;
    while (attempt <= this.maxRetries) {
      try {
        if (attempt > 0) {
          this.logger.debug(
            `Retrying Anthropic ${context} attempt ${attempt}/${this.maxRetries}`,
          );
        }
        return await fn();
      } catch (err: any) {
        lastError = err;
        const { retryable, reason } = this.isRetryableAnthropicError(err);
        if (!retryable || attempt === this.maxRetries) {
          if (retryable) {
            this.logger.error(
              `Anthropic ${context} failed after ${attempt} retries: ${reason}: ${err.message}`,
            );
          }
          break;
        }
        const delay = this.computeBackoffDelay(attempt);
        this.logger.warn(
          `Transient Anthropic error (${reason}) on ${context}: ${err.message} | waiting ${delay}ms before retry ${attempt + 1}`,
        );
        await this.delay(delay);
        attempt++;
      }
    }
    throw lastError;
  }

  private isRetryableAnthropicError(error: any): { retryable: boolean; reason: string } {
    // Anthropic SDK error may have status / error fields
    const status = error?.status || error?.response?.status;
    const errorType = error?.error?.type || error?.data?.error?.type;
    if (['overloaded_error', 'rate_limit_error', 'timeout_error'].includes(errorType)) {
      return { retryable: true, reason: errorType };
    }
    if ([408, 409, 425, 429, 500, 502, 503, 504, 529].includes(status)) {
      return { retryable: true, reason: `http_${status}` };
    }
    return { retryable: false, reason: 'non_retryable' };
  }

  private computeBackoffDelay(attempt: number): number {
    // attempt 0 = first try (no delay). For retries, start at base * 2^(attempt-1)
    if (attempt === 0) return 0;
    const exp = this.baseRetryDelayMs * 2 ** (attempt - 1);
    const jitter = Math.floor(Math.random() * Math.min(250, this.baseRetryDelayMs));
    return Math.min(exp + jitter, 15000); // cap at 15s per attempt
  }

  private delay(ms: number): Promise<void> {
    return new Promise((res) => setTimeout(res, ms));
  }

  /**
   * Convert our MessageContentBlock format to Anthropic's message format
   */
  private formatMessagesForAnthropic(
    messages: Message[],
  ): Anthropic.MessageParam[] {
    const anthropicMessages: Anthropic.MessageParam[] = [];

    // Process each message content block
    for (const [index, message] of messages.entries()) {
      const messageContentBlocks = message.content as MessageContentBlock[];

      const content: Anthropic.ContentBlockParam[] = [];

      if (
        messageContentBlocks.every((block) => isUserActionContentBlock(block))
      ) {
        const userActionContentBlocks = messageContentBlocks.flatMap(
          (block) => block.content,
        );
        for (const block of userActionContentBlocks) {
          if (isComputerToolUseContentBlock(block)) {
            content.push({
              type: 'text',
              text: `User performed action: ${block.name}\n${JSON.stringify(block.input, null, 2)}`,
            });
          } else {
            content.push(block as Anthropic.ContentBlockParam);
          }
        }
      } else {
        content.push(
          ...messageContentBlocks.map(
            (block) => block as Anthropic.ContentBlockParam,
          ),
        );
      }

      if (index === messages.length - 1) {
        content[content.length - 1]['cache_control'] = {
          type: 'ephemeral',
        };
      }
      anthropicMessages.push({
        role: message.role === Role.USER ? 'user' : 'assistant',
        content: content,
      });
    }

    return anthropicMessages;
  }

  /**
   * Convert Anthropic's response content to our MessageContentBlock format
   */
  private formatAnthropicResponse(
    content: Anthropic.ContentBlock[],
  ): MessageContentBlock[] {
    return content.map((block) => {
      switch (block.type) {
        case 'text':
          return {
            type: MessageContentType.Text,
            text: block.text,
          } as TextContentBlock;

        case 'tool_use':
          return {
            type: MessageContentType.ToolUse,
            id: block.id,
            name: block.name,
            input: block.input,
          } as ToolUseContentBlock;

        case 'thinking':
          return {
            type: MessageContentType.Thinking,
            thinking: block.thinking,
            signature: block.signature,
          } as ThinkingContentBlock;

        case 'redacted_thinking':
          return {
            type: MessageContentType.RedactedThinking,
            data: block.data,
          } as RedactedThinkingContentBlock;
      }
    });
  }
}
