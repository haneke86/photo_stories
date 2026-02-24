import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE_NAME = process.env.USAGE_TABLE_NAME!;
const STORIES_LIMIT = parseInt(process.env.STORIES_LIMIT ?? "5", 10);
const CHATS_LIMIT = parseInt(process.env.CHATS_LIMIT ?? "20", 10);

export interface UsageRecord {
  userId: string;
  storiesUsed: number;
  chatsUsed: number;
  periodStart: string;
  createdAt: string;
}

/** Get the ISO date string of the 1st of the current month. */
function currentPeriodStart(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-01`;
}

/** Get the ISO date string of the 1st of next month (for resetsAt). */
export function nextPeriodStart(): string {
  const now = new Date();
  const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  return nextMonth.toISOString().slice(0, 10);
}

/**
 * Check if the user can use a resource, and increment if allowed.
 * Uses DynamoDB conditional update for atomicity.
 * Auto-resets counters when the period has rolled over.
 */
export async function checkAndIncrement(
  userId: string,
  type: "stories" | "chats",
): Promise<{ allowed: boolean; remaining: number }> {
  const period = currentPeriodStart();
  const limit = type === "stories" ? STORIES_LIMIT : CHATS_LIMIT;
  const countField = type === "stories" ? "storiesUsed" : "chatsUsed";

  // First, ensure the user record exists and the period is current.
  // If periodStart is stale, reset both counters.
  await ddb.send(
    new UpdateCommand({
      TableName: TABLE_NAME,
      Key: { userId },
      UpdateExpression:
        "SET periodStart = if_not_exists(periodStart, :period), " +
        "storiesUsed = if_not_exists(storiesUsed, :zero), " +
        "chatsUsed = if_not_exists(chatsUsed, :zero), " +
        "createdAt = if_not_exists(createdAt, :now)",
      ExpressionAttributeValues: {
        ":period": period,
        ":zero": 0,
        ":now": new Date().toISOString(),
      },
    }),
  );

  // Check if period needs reset
  const current = await ddb.send(
    new GetCommand({ TableName: TABLE_NAME, Key: { userId } }),
  );
  const item = current.Item as UsageRecord | undefined;

  if (item && item.periodStart < period) {
    // Period rolled over — reset counters
    await ddb.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { userId },
        UpdateExpression: "SET storiesUsed = :zero, chatsUsed = :zero, periodStart = :period",
        ExpressionAttributeValues: { ":zero": 0, ":period": period },
      }),
    );
  }

  // Atomic conditional increment: only if under limit
  try {
    const result = await ddb.send(
      new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { userId },
        UpdateExpression: `SET #count = #count + :one`,
        ConditionExpression: "#count < :limit",
        ExpressionAttributeNames: { "#count": countField },
        ExpressionAttributeValues: { ":one": 1, ":limit": limit },
        ReturnValues: "ALL_NEW",
      }),
    );

    const updated = result.Attributes as UsageRecord;
    const used = type === "stories" ? updated.storiesUsed : updated.chatsUsed;
    return { allowed: true, remaining: limit - used };
  } catch (err: unknown) {
    if ((err as { name?: string }).name === "ConditionalCheckFailedException") {
      return { allowed: false, remaining: 0 };
    }
    throw err;
  }
}

/** Get current usage for a user. */
export async function getUsage(userId: string): Promise<{
  stories: { used: number; limit: number };
  chats: { used: number; limit: number };
  resetsAt: string;
}> {
  const period = currentPeriodStart();

  const result = await ddb.send(
    new GetCommand({ TableName: TABLE_NAME, Key: { userId } }),
  );

  const item = result.Item as UsageRecord | undefined;

  // If no record or period is stale, return fresh counters
  if (!item || item.periodStart < period) {
    return {
      stories: { used: 0, limit: STORIES_LIMIT },
      chats: { used: 0, limit: CHATS_LIMIT },
      resetsAt: nextPeriodStart(),
    };
  }

  return {
    stories: { used: item.storiesUsed, limit: STORIES_LIMIT },
    chats: { used: item.chatsUsed, limit: CHATS_LIMIT },
    resetsAt: nextPeriodStart(),
  };
}
