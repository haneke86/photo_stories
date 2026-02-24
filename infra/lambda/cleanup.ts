import type { ScheduledEvent } from "aws-lambda";
import {
  CognitoIdentityProviderClient,
  AdminDeleteUserCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  ScanCommand,
  DeleteCommand,
} from "@aws-sdk/lib-dynamodb";

const cognitoClient = new CognitoIdentityProviderClient({});
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const DELETIONS_TABLE = process.env.DELETIONS_TABLE_NAME!;
const USAGE_TABLE = process.env.USAGE_TABLE_NAME!;
const USER_POOL_ID = process.env.COGNITO_USER_POOL_ID!;

/**
 * Scheduled cleanup handler — runs daily via EventBridge.
 * Permanently deletes accounts whose grace period has expired.
 */
export async function handler(_event: ScheduledEvent): Promise<void> {
  const now = new Date().toISOString();
  console.log(`Cleanup started at ${now}`);

  // Scan for pending deletions where grace period has expired
  const result = await ddb.send(
    new ScanCommand({
      TableName: DELETIONS_TABLE,
      FilterExpression: "#s = :pending AND deleteAfter < :now",
      ExpressionAttributeNames: { "#s": "status" },
      ExpressionAttributeValues: {
        ":pending": "pending",
        ":now": now,
      },
    }),
  );

  const items = result.Items ?? [];
  console.log(`Found ${items.length} expired deletion requests`);

  for (const item of items) {
    const userId = item.userId as string;
    console.log(`Processing deletion for user: ${userId}`);

    try {
      // 1. Delete user from Cognito
      await cognitoClient.send(
        new AdminDeleteUserCommand({
          UserPoolId: USER_POOL_ID,
          Username: userId,
        }),
      );
      console.log(`Deleted Cognito user: ${userId}`);
    } catch (err: unknown) {
      // User may already be deleted from Cognito — continue cleanup
      if ((err as { name?: string }).name === "UserNotFoundException") {
        console.log(`Cognito user already deleted: ${userId}`);
      } else {
        console.error(`Failed to delete Cognito user ${userId}:`, err);
        continue; // Skip this user, retry on next run
      }
    }

    try {
      // 2. Delete usage record
      await ddb.send(
        new DeleteCommand({
          TableName: USAGE_TABLE,
          Key: { userId },
        }),
      );
      console.log(`Deleted usage record: ${userId}`);

      // 3. Delete deletion request record
      await ddb.send(
        new DeleteCommand({
          TableName: DELETIONS_TABLE,
          Key: { userId },
        }),
      );
      console.log(`Deleted deletion record: ${userId}`);
    } catch (err) {
      console.error(`Failed to clean up DynamoDB records for ${userId}:`, err);
      // Don't continue — Cognito user is already deleted, so mark as best-effort
    }
  }

  console.log(`Cleanup completed. Processed ${items.length} deletions.`);
}
