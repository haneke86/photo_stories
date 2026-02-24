#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { MacPhotoStack } from "./macphoto-stack";

const app = new cdk.App();

new MacPhotoStack(app, "MacPhotoStack", {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION ?? "us-east-1",
  },
});
