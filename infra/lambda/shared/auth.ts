import {
  CognitoIdentityProviderClient,
  AdminGetUserCommand,
} from "@aws-sdk/client-cognito-identity-provider";
import { CognitoJwtVerifier } from "aws-jwt-verify";

const cognitoClient = new CognitoIdentityProviderClient({});

let verifier: ReturnType<typeof CognitoJwtVerifier.create> | null = null;

function getVerifier() {
  if (!verifier) {
    verifier = CognitoJwtVerifier.create({
      userPoolId: process.env.COGNITO_USER_POOL_ID!,
      clientId: process.env.COGNITO_CLIENT_ID!,
      tokenUse: "id",
    });
  }
  return verifier;
}

/**
 * Validate a JWT from the Authorization header and return the user's sub (userId).
 * Used by the chat Lambda Function URL which bypasses API Gateway's authorizer.
 */
export async function validateJwtAndGetUserId(authHeader: string | undefined): Promise<string | null> {
  if (!authHeader) return null;

  const token = authHeader.startsWith("Bearer ")
    ? authHeader.slice(7)
    : authHeader;

  try {
    const payload = await getVerifier().verify(token);
    return payload.sub;
  } catch {
    return null;
  }
}

/** Extract userId from API Gateway Cognito authorizer context. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function getUserIdFromApiGw(event: any): string | null {
  return event?.requestContext?.authorizer?.jwt?.claims?.sub ?? null;
}

/**
 * Get the stable Apple subject ID for a Cognito user.
 * Reads the `identities` attribute which contains a JSON array of federated providers.
 * Returns the Apple provider's userId (the stable Apple sub) or null if not found.
 */
export async function getAppleSubject(userPoolId: string, username: string): Promise<string | null> {
  const result = await cognitoClient.send(
    new AdminGetUserCommand({
      UserPoolId: userPoolId,
      Username: username,
    }),
  );

  const identitiesAttr = result.UserAttributes?.find(
    (attr) => attr.Name === "identities",
  );
  if (!identitiesAttr?.Value) return null;

  try {
    const identities = JSON.parse(identitiesAttr.Value) as Array<{
      userId?: string;
      providerName?: string;
    }>;
    const apple = identities.find((id) => id.providerName === "SignInWithApple");
    return apple?.userId ?? null;
  } catch {
    return null;
  }
}
