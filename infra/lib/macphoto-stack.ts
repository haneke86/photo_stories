import * as cdk from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as events from "aws-cdk-lib/aws-events";
import * as targets from "aws-cdk-lib/aws-events-targets";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as nodejs from "aws-cdk-lib/aws-lambda-nodejs";
import * as apigwv2 from "aws-cdk-lib/aws-apigatewayv2";
import * as apigwv2Integrations from "aws-cdk-lib/aws-apigatewayv2-integrations";
import * as apigwv2Authorizers from "aws-cdk-lib/aws-apigatewayv2-authorizers";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import { Construct } from "constructs";
import * as path from "path";

export class MacPhotoStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // ─── Cognito User Pool (Sign in with Apple) ───

    const userPool = new cognito.UserPool(this, "MacPhotoUserPool", {
      userPoolName: "macphoto-users",
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      autoVerify: { email: true },
      standardAttributes: {
        email: { required: true, mutable: true },
      },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Cognito domain for hosted UI (OAuth2 code flow)
    const cognitoDomain = userPool.addDomain("CognitoDomain", {
      cognitoDomain: { domainPrefix: "macphoto-auth" },
    });

    // Apple identity provider
    const appleProvider = new cognito.UserPoolIdentityProviderApple(this, "AppleProvider", {
      userPool,
      clientId: "com.macphoto.trips.signin",
      teamId: "SFN3S2CR7S",
      keyId: "SMVA85X274",
      privateKey: `-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgn3O7Sydtk/K99uDP
QRzvsH+DqGiOw0HpHYS8WllPtAygCgYIKoZIzj0DAQehRANCAATTg7lNqW938fDv
pFE007AQ2RXrSCaOOf1keE92wj9+lXKTqYsAOFp2QhZHtvzrsoUsn3AaSxGUbO/w
oqj17kEC
-----END PRIVATE KEY-----`,
      scopes: ["email", "name"],
      attributeMapping: {
        email: cognito.ProviderAttribute.APPLE_EMAIL,
        fullname: cognito.ProviderAttribute.APPLE_NAME,
      },
    });

    const userPoolClient = new cognito.UserPoolClient(this, "MacPhotoClient", {
      userPool,
      userPoolClientName: "macphoto-ios",
      generateSecret: false,
      oAuth: {
        flows: { authorizationCodeGrant: true },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls: ["macphoto://auth/callback"],
        logoutUrls: ["macphoto://auth/logout"],
      },
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.APPLE,
      ],
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
      preventUserExistenceErrors: true,
    });

    userPoolClient.node.addDependency(appleProvider);

    // ─── DynamoDB Usage Table ───

    const usageTable = new dynamodb.Table(this, "UsageTable", {
      tableName: "macphoto-usage",
      partitionKey: { name: "userId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // ─── DynamoDB Deletions Table ───

    const deletionsTable = new dynamodb.Table(this, "DeletionsTable", {
      tableName: "macphoto-deletions",
      partitionKey: { name: "userId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    deletionsTable.addGlobalSecondaryIndex({
      indexName: "appleSubject-index",
      partitionKey: { name: "appleSubject", type: dynamodb.AttributeType.STRING },
    });

    // ─── Secrets Manager (Anthropic API Key) ───

    // Import existing secret or create placeholder.
    // After deploy, store your key: aws secretsmanager put-secret-value --secret-id macphoto/anthropic-api-key --secret-string "sk-ant-..."
    const anthropicSecret = new secretsmanager.Secret(this, "AnthropicApiKey", {
      secretName: "macphoto/anthropic-api-key",
      description: "Anthropic API key for MacPhotoTrips LLM proxy",
    });

    // ─── Shared Lambda Environment ───

    const lambdaEnv = {
      USAGE_TABLE_NAME: usageTable.tableName,
      STORIES_LIMIT: "5",
      CHATS_LIMIT: "20",
      ANTHROPIC_SECRET_ARN: anthropicSecret.secretArn,
      COGNITO_USER_POOL_ID: userPool.userPoolId,
      COGNITO_CLIENT_ID: userPoolClient.userPoolClientId,
      COGNITO_REGION: this.region,
    };

    const lambdaDir = path.join(__dirname, "..", "lambda");

    // ─── Lambda: Story Proxy ───

    const proxyFn = new nodejs.NodejsFunction(this, "ProxyFunction", {
      functionName: "macphoto-proxy",
      entry: path.join(lambdaDir, "proxy.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 256,
      timeout: cdk.Duration.seconds(60),
      environment: lambdaEnv,
      bundling: {
        minify: true,
        sourceMap: true,
        target: "node22",
      },
    });

    // ─── Lambda: Chat (Streaming via Function URL) ───

    const chatFn = new nodejs.NodejsFunction(this, "ChatFunction", {
      functionName: "macphoto-chat",
      entry: path.join(lambdaDir, "chat.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 256,
      timeout: cdk.Duration.seconds(120),
      environment: lambdaEnv,
      bundling: {
        minify: true,
        sourceMap: true,
        target: "node22",
      },
    });

    // Function URL for SSE streaming (API Gateway doesn't support SSE)
    const chatFnUrl = chatFn.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.NONE, // JWT validated manually in handler
      invokeMode: lambda.InvokeMode.RESPONSE_STREAM,
      cors: {
        allowedOrigins: ["*"],
        allowedMethods: [lambda.HttpMethod.POST],
        allowedHeaders: ["Content-Type", "Authorization"],
      },
    });

    // ─── Lambda: Usage ───

    const usageFn = new nodejs.NodejsFunction(this, "UsageFunction", {
      functionName: "macphoto-usage",
      entry: path.join(lambdaDir, "usage.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 128,
      timeout: cdk.Duration.seconds(10),
      environment: lambdaEnv,
      bundling: {
        minify: true,
        sourceMap: true,
        target: "node22",
      },
    });

    // ─── Lambda: Account Deletion ───

    const accountFn = new nodejs.NodejsFunction(this, "AccountFunction", {
      functionName: "macphoto-account",
      entry: path.join(lambdaDir, "account.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 128,
      timeout: cdk.Duration.seconds(30),
      environment: {
        DELETIONS_TABLE_NAME: deletionsTable.tableName,
        USAGE_TABLE_NAME: usageTable.tableName,
        COGNITO_USER_POOL_ID: userPool.userPoolId,
      },
      bundling: {
        minify: true,
        sourceMap: true,
        target: "node22",
      },
    });

    // ─── Lambda: Cleanup (Scheduled) ───

    const cleanupFn = new nodejs.NodejsFunction(this, "CleanupFunction", {
      functionName: "macphoto-cleanup",
      entry: path.join(lambdaDir, "cleanup.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      architecture: lambda.Architecture.ARM_64,
      memorySize: 128,
      timeout: cdk.Duration.seconds(120),
      environment: {
        DELETIONS_TABLE_NAME: deletionsTable.tableName,
        USAGE_TABLE_NAME: usageTable.tableName,
        COGNITO_USER_POOL_ID: userPool.userPoolId,
      },
      bundling: {
        minify: true,
        sourceMap: true,
        target: "node22",
      },
    });

    // ─── EventBridge: Daily Cleanup Schedule ───

    new events.Rule(this, "CleanupSchedule", {
      ruleName: "macphoto-cleanup-daily",
      schedule: events.Schedule.cron({ hour: "3", minute: "0" }),
      targets: [new targets.LambdaFunction(cleanupFn)],
    });

    // ─── IAM Permissions ───

    usageTable.grantReadWriteData(proxyFn);
    usageTable.grantReadWriteData(chatFn);
    usageTable.grantReadData(usageFn);
    // Usage fn also needs write to reset expired periods
    usageTable.grantWriteData(usageFn);

    anthropicSecret.grantRead(proxyFn);
    anthropicSecret.grantRead(chatFn);

    // Account Lambda: read/write deletions, Cognito AdminGetUser + AdminDisableUser
    deletionsTable.grantReadWriteData(accountFn);
    accountFn.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["cognito-idp:AdminGetUser", "cognito-idp:AdminDisableUser"],
        resources: [userPool.userPoolArn],
      }),
    );

    // Cleanup Lambda: read/write deletions, read/write usage (delete records), Cognito AdminDeleteUser
    deletionsTable.grantReadWriteData(cleanupFn);
    usageTable.grantReadWriteData(cleanupFn);
    cleanupFn.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["cognito-idp:AdminDeleteUser"],
        resources: [userPool.userPoolArn],
      }),
    );

    // ─── API Gateway HTTP API ───

    const httpApi = new apigwv2.HttpApi(this, "MacPhotoApi", {
      apiName: "macphoto-api",
      corsPreflight: {
        allowOrigins: ["*"],
        allowMethods: [
          apigwv2.CorsHttpMethod.GET,
          apigwv2.CorsHttpMethod.POST,
          apigwv2.CorsHttpMethod.DELETE,
          apigwv2.CorsHttpMethod.OPTIONS,
        ],
        allowHeaders: ["Content-Type", "Authorization"],
      },
    });

    // Cognito JWT Authorizer
    const authorizer = new apigwv2Authorizers.HttpUserPoolAuthorizer(
      "CognitoAuthorizer",
      userPool,
      { userPoolClients: [userPoolClient] },
    );

    // Routes
    httpApi.addRoutes({
      path: "/api/v1/stories/generate",
      methods: [apigwv2.HttpMethod.POST],
      integration: new apigwv2Integrations.HttpLambdaIntegration("ProxyGenerate", proxyFn),
      authorizer,
    });

    httpApi.addRoutes({
      path: "/api/v1/stories/single",
      methods: [apigwv2.HttpMethod.POST],
      integration: new apigwv2Integrations.HttpLambdaIntegration("ProxySingle", proxyFn),
      authorizer,
    });

    httpApi.addRoutes({
      path: "/api/v1/usage",
      methods: [apigwv2.HttpMethod.GET],
      integration: new apigwv2Integrations.HttpLambdaIntegration("UsageGet", usageFn),
      authorizer,
    });

    httpApi.addRoutes({
      path: "/api/v1/account",
      methods: [apigwv2.HttpMethod.DELETE],
      integration: new apigwv2Integrations.HttpLambdaIntegration("AccountDelete", accountFn),
      authorizer,
    });

    // ─── Outputs ───

    new cdk.CfnOutput(this, "ApiUrl", {
      value: httpApi.apiEndpoint,
      description: "API Gateway endpoint URL",
    });

    new cdk.CfnOutput(this, "ChatStreamUrl", {
      value: chatFnUrl.url,
      description: "Chat Lambda Function URL (SSE streaming)",
    });

    new cdk.CfnOutput(this, "UserPoolId", {
      value: userPool.userPoolId,
      description: "Cognito User Pool ID",
    });

    new cdk.CfnOutput(this, "UserPoolClientId", {
      value: userPoolClient.userPoolClientId,
      description: "Cognito User Pool Client ID",
    });

    new cdk.CfnOutput(this, "AnthropicSecretArn", {
      value: anthropicSecret.secretArn,
      description: "ARN for storing Anthropic API key",
    });

    new cdk.CfnOutput(this, "CognitoDomainUrl", {
      value: `https://${cognitoDomain.domainName}.auth.${this.region}.amazoncognito.com`,
      description: "Cognito hosted UI domain URL",
    });
  }
}
