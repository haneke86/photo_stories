import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import { getUserIdFromApiGw } from "./shared/auth";
import { checkAndIncrement, nextPeriodStart } from "./shared/usage-db";
import { callAnthropic } from "./shared/anthropic-client";

/**
 * Story generation proxy — handles both batch narratives and single stories.
 *
 * POST /api/v1/stories/generate — batch narratives (mirrors generateNarratives)
 * POST /api/v1/stories/single   — single story (mirrors generateSingleStory)
 */
export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  try {
    const userId = getUserIdFromApiGw(event);
    if (!userId) {
      return response(401, { error: "Unauthorized" });
    }

    // Check usage
    const usage = await checkAndIncrement(userId, "stories");
    if (!usage.allowed) {
      return response(429, {
        error: "Monthly story limit reached",
        remaining: 0,
        resetsAt: nextPeriodStart(),
      });
    }

    const body = JSON.parse(event.body ?? "{}");
    const path = event.requestContext.http.path;

    let anthropicBody: Record<string, unknown>;

    if (path.endsWith("/stories/generate")) {
      // Batch narratives — forward the full request to Anthropic
      anthropicBody = {
        model: body.model ?? "claude-sonnet-4-5-20250929",
        max_tokens: body.max_tokens ?? 8192,
        system: body.systemPrompt ?? body.system,
        messages: body.messages,
      };
    } else if (path.endsWith("/stories/single")) {
      // Single story
      anthropicBody = {
        model: body.model ?? "claude-sonnet-4-5-20250929",
        max_tokens: body.max_tokens ?? 1024,
        system: body.systemPrompt ?? body.system,
        messages: body.messages ?? [
          { role: "user", content: body.userMessage },
        ],
      };
    } else {
      return response(404, { error: "Not found" });
    }

    const result = await callAnthropic(anthropicBody);

    return response(200, {
      ...result as Record<string, unknown>,
      _usage: { remaining: usage.remaining },
    });
  } catch (err) {
    console.error("Proxy error:", err);
    return response(500, { error: "Internal server error" });
  }
}

function response(statusCode: number, body: unknown): APIGatewayProxyResultV2 {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}
