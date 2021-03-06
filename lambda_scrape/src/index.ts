import {
	APIGatewayProxyEvent,
	APIGatewayProxyResult
} from "aws-lambda"

import S3 from './s3'
import Lambda from './lambda'

import {promisify} from 'util'
import { exec as execCb} from 'child_process'
const exec = promisify(execCb)

const {S3_REGION, S3_BUCKET, LAMBDA_ANALYZE} = process.env
if (!S3_REGION || !S3_BUCKET || !LAMBDA_ANALYZE){
	console.debug('S3_REGION', S3_REGION)
	console.debug('S3_BUCKET', S3_BUCKET)
	console.debug('LAMBDA_ANALYZE', LAMBDA_ANALYZE)
	throw new Error("S3_REGION OR S3_BUCKET or LAMBDA_ANALYZE env missing")
}
const s3 = S3(S3_REGION, S3_BUCKET)
const lambda = Lambda(S3_REGION) 
const DATA_USA_S3_KEY = "datausa.api.json"


export const lambdaHandler = async (
	event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
	// const queries = JSON.stringify(event.queryStringParameters);

	const s3ModifiedFiles = await s3.syncDirectoryToS3("https://download.bls.gov/pub/time.series/pr/", [
		DATA_USA_S3_KEY,
		"analysis.ipynb",
		"analysis.html"
	])
	const dataUSAModified = await s3.copyHTTPResourceToS3("https://datausa.io/api/data?drilldowns=Nation&measures=Population", DATA_USA_S3_KEY)
	const rerenderAnalysis = s3ModifiedFiles.includes("pr.data.0.Current") || dataUSAModified
	if (rerenderAnalysis){
		await lambda.invoke(LAMBDA_ANALYZE)
	}

	return {
		statusCode: 200,
		body: `
			modified files: ${s3ModifiedFiles}
			modified ${DATA_USA_S3_KEY}: ${dataUSAModified}
			analysis rerendered: ${rerenderAnalysis}
		`
	}
}
