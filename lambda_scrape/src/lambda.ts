import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda"; // ES Modules import
export default (region:string) => {
	const client = new LambdaClient({region})
	const invoke = async (functionName: string) => {
		const command = new InvokeCommand({
			FunctionName: functionName
		});
		const response = await client.send(command)
		return response
	}
	return {
		invoke
	}
}