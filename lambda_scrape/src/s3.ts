import { S3Client, ListObjectsV2Command, PutObjectCommand, DeleteObjectsCommand, HeadObjectCommand} from "@aws-sdk/client-s3"
import {Readable} from "stream"
import {basename} from 'path'

import { fetch } from "undici"
import { scrapeDirectoryListing } from "./scrape"

export default (region: string, bucket: string) => {
	const s3Client = new S3Client({region})
	const streamResponseToS3 = async (file: string, response: any /*Response*/) : Promise<boolean> => {
		const {body, status, headers} = response
			// we already have this file
		// 304 (Not Modified)
		if (status === 304){
			console.debug(`skipping upload of ${file}, s3 version up-to-date`)
			return false
		}
			

		if (status !== 200 || !body)
			throw new Error(`error, got http status ${status} for file: ${file}, url: ${response.url}`)

		/*
		Nodejs has two kinds of streams: web streams which follow the API of the WHATWG web standard found in browsers, and an older Node-specific streams API. response.body returns a readable web stream. If you would prefer to work with a Node stream you can convert a web stream using .from().
		*/
		let contentLength:number
		const etag = headers.get('ETag')
		const lastModified = headers.get('Last-Modified')
		const len = headers.get('Content-Length')
		let fileData : Buffer | Readable
		if (len){
			contentLength = +len
			fileData = Readable.from(body)
		}else{
			console.debug(`performance warning (have to dl entire file): missing Content-Length header for file: ${file}, url: ${response.url}`)
			const buf = await response.arrayBuffer()
			fileData = buf
			contentLength = buf.byteLength
		}
		await s3PutObject(file, fileData, contentLength, {
			...etag && {ETag: etag},
			...lastModified && {LastModified: lastModified}
		})

		return true
	}

	const s3PutObject =  async (key: string, body: Readable | Buffer, contentLength: number, metadata: Record<string, string>) => {
		console.debug(
			`putting object onto s3, key ${key}, len: ${contentLength}, metadata `, metadata
		)
		const command = new PutObjectCommand({Bucket: bucket, Key: key, Body: body, ContentLength: contentLength, Metadata: metadata})
		const response = await s3Client.send(command)
		return response
	}

	const s3MetaData = async (fileKey: string) => {
		const command = new HeadObjectCommand({Bucket: bucket, Key: fileKey})
		const response = await s3Client.send(command)
		const metadata = response.Metadata
		console.debug(`got s3 metadata for ${fileKey}`, metadata)
		return metadata
	}

	const s3Delete = async (keys: string[]) => {
		console.debug(`deleting s3 objects: `, keys)
		const command = new DeleteObjectsCommand({Bucket: bucket, Delete: undefined})
		while (keys.length)
		{
			// send batch requests of 1000 files at once
			command.input.Delete = {Objects: keys.splice(-1000, 1000).map(
				x => ({Key: x})
			)}
			const response = await s3Client.send(command)
		}
	}

	const getS3FileNames = async () : Promise<string[]> => {
		const command = new ListObjectsV2Command({Bucket: bucket})
		const s3FileNames : string[] = []
		for (;;)
		{
			const response = await s3Client.send(command)
			if (response.Contents)
				s3FileNames.push(...response.Contents.map(x => x.Key || "").filter(x => x && !x.endsWith("/")))

			if (response.IsTruncated)
				command.input.ContinuationToken = response.ContinuationToken
			else break
		} 
		return s3FileNames
	}

	const syncDirectoryToS3 = async (dirURLStr: string, ignoreFiles: string[]=[]): Promise<string[]> => {
		const fileURLs = await scrapeDirectoryListing(new URL(dirURLStr))
		const fileSet = new Map(
			fileURLs.map(x => [basename(x.pathname), x])
		)

		const s3FileNames = new Set(await getS3FileNames())
		for (const file of ignoreFiles)
			s3FileNames.delete(file)

		// delete all files that don't exist in the newly fetched directory listing
		const toDelete = [...s3FileNames].filter(x => !fileSet.has(x))
		const modifiedFiles = [...toDelete]
		await s3Delete(toDelete)

		
		// upload files which we don't already have the same copy of
		for (const [file, url] of fileSet){
			let s3ETag, s3LastModified
			// if we have the file already, we need to check its E-Tag tag (different from S3 E-Tag)
			if (s3FileNames.has(file)){
				const metadata = await s3MetaData(file)
				s3ETag = metadata?.etag
				s3LastModified = metadata?.lastmodified
			}
			
			console.debug(`fetching ${url}`)
			const response = await fetch(url, {
				headers: {
					...s3ETag && {'If-None-Match': s3ETag},
					...s3LastModified && {'If-Modified-Since': s3LastModified}
				}
			})

			const modified = await streamResponseToS3(file, response)
			if (modified)
				modifiedFiles.push(file)
		}
		return modifiedFiles
	}

	const copyHTTPResourceToS3 = async (url: string, key: string) : Promise<boolean> => {
		let metadata
		try {
			metadata = await s3MetaData(key)
		} catch(e) {
			if (!(e instanceof Error && e.name == "NotFound"))
				throw e
		}
		const s3ETag = metadata?.etag
		const s3LastModified = metadata?.lastmodified
		const response = await fetch(url, {
			headers: {
				...s3ETag && {'If-None-Match': s3ETag},
				...s3LastModified && {'If-Modified-Since': s3LastModified}
			}
		})
		const modified = await streamResponseToS3(key, response)
		return modified
	}

	return {syncDirectoryToS3, copyHTTPResourceToS3}
}