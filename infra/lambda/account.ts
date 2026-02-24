import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2 } from "aws-lambda";
import {
  CognitoIdentityProviderClient,
  AdminDisableUserCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import { getUserIdFromApiGw, getAppleSubject } from "./shared/auth";

const cognitoClient = new CognitoIdentityProviderClient({});
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const DELETIONS_TABLE = process.env.DELETIONS_TABLE_NAME!;
const USER_POOL_ID = process.env.COGNITO_USER_POOL_ID!;

/** Grace period before permanent deletion (30 days). */
const DELETION_GRACE_DAYS = 30;

/**
 * Account deletion handler.
 * DELETE /api/v1/account — schedule account for deletion after 30-day grace period.
 */
export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyResultV2> {
  try {
    const userId = getUserIdFromApiGw(event);
    if (!userId) {
      return response(401, { error: "Unauthorized" });
    }

    // Check for existing pending deletion
    const existing = await ddb.send(
      new GetCommand({
        TableName: DELETIONS_TABLE,
        Key: { userId },
      }),
    );

    if (existing.Item && existing.Item.status === "pending") {
      return response(409, {
        error: "Account deletion already scheduled",
        deleteAfter: existing.Item.deleteAfter,
      });
    }

    // Get Apple subject for re-signup protection
    const appleSubject = await getAppleSubject(USER_POOL_ID, userId);

    // Calculate deletion date (30 days from now)
    const now = new Date();
    const deleteAfter = new Date(now.getTime() + DELETION_GRACE_DAYS * 24 * 60 * 60 * 1000);
    const deleteAfterIso = deleteAfter.toISOString();

    // Write deletion record
    await ddb.send(
      new PutCommand({
        TableName: DELETIONS_TABLE,
        Item: {
          userId,
          appleSubject: appleSubject ?? "unknown",
          requestedAt: now.toISOString(),
          deleteAfter: deleteAfterIso,
          status: "pending",
        },
      }),
    );

    // Disable user in Cognito to prevent sign-in during grace period
    await cognitoClient.send(
      new AdminDisableUserCommand({
        UserPoolId: USER_POOL_ID,
        Username: userId,
      }),
    );

    return response(200, {
      scheduled: true,
      deleteAfter: deleteAfterIso,
    });
  } catch (err) {
    console.error("Account deletion error:", err);
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
