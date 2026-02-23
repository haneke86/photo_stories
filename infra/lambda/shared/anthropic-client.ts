import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from "@aws-sdk/client-secrets-manager";

const secretsClient = new SecretsManagerClient({});

let cachedApiKey: string | null = null;

/** Fetch Anthropic API key from Secrets Manager (cached per cold start). */
export async function getAnthropicApiKey(): Promise<string> {
  if (cachedApiKey) return cachedApiKey;

  const result = await secretsClient.send(
    new GetSecretValueCommand({
      SecretId: process.env.ANTHROPIC_SECRET_ARN!,
    }),
  );

  const raw = result.SecretString ?? "";
  if (!raw) throw new Error("Anthropic API key not found in Secrets Manager");

  // Secret may be stored as JSON {"ANTHROPIC_API_KEY":"sk-ant-..."} or as a plain string
  try {
    const parsed = JSON.parse(raw);
    cachedApiKey = parsed.ANTHROPIC_API_KEY ?? raw;
  } catch {
    cachedApiKey = raw; // plain string
  }

  return cachedApiKey;
}

/** Forward a request body to the Anthropic Messages API (non-streaming). */
export async function callAnthropic(body: Record<string, unknown>): Promise<unknown> {
  const apiKey = await getAnthropicApiKey();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Anthropic API error ${response.status}: ${errorBody}`);
  }

  return response.json();
}

/** Open a streaming connection to the Anthropic Messages API. Returns a ReadableStream. */
export async function streamAnthropic(body: Record<string, unknown>): Promise<ReadableStream<Uint8Array>> {
  const apiKey = await getAnthropicApiKey();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({ ...body, stream: true }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Anthropic API error ${response.status}: ${errorBody}`);
  }

  if (!response.body) {
    throw new Error("No response body from Anthropic streaming endpoint");
  }

  return response.body;
}
