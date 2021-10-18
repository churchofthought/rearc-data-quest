import {
	APIGatewayProxyEvent,
	APIGatewayProxyResult
} from "aws-lambda"

import S3 from './s3'

import {promisify} from 'util'
import { exec as execCb} from 'child_process'
const exec = promisify(execCb)

const {S3_REGION, S3_BUCKET} = process.env
if (!S3_REGION || !S3_BUCKET){
	console.debug('S3_REGION', S3_REGION)
	console.debug('S3_BUCKET', S3_BUCKET)
	throw new Error(`S3_REGION OR S3_BUCKET env missing`)
}
const s3 = S3(S3_REGION, S3_BUCKET)
const DATA_USA_S3_KEY = "datausa.api.json"

const renderAnalysis = async () => {
	await exec(`papermill local/analysis.ipynb s3://${S3_BUCKET}/analysis.ipynb`)
}

export const lambdaHandler = async (
	event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
	const queries = JSON.stringify(event.queryStringParameters);

	const s3ModifiedFiles = await s3.syncDirectoryToS3("https://download.bls.gov/pub/time.series/pr/", [
		DATA_USA_S3_KEY
	])
	const dataUSAModified = await s3.copyHTTPResourceToS3("https://datausa.io/api/data?drilldowns=Nation&measures=Population", DATA_USA_S3_KEY)
	const rerenderAnalysis = s3ModifiedFiles.includes("pr.data.0.Current") || dataUSAModified
	if (rerenderAnalysis){
		//await renderAnalysis()
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