import { fetch } from "undici"

// Avoid creating a regular expression everytime method is ran
// https://stackoverflow.com/questions/8814009/how-often-does-javascript-recompile-regex-literals-in-functions/32524171#32524171
// matches only files, not directories (which always end in slash)
const reFileURL = /<A HREF="([^"]+?[^\/])">/ig

const getFileURLsFromDirectoryListing = async (dirURL: URL) : Promise<string[]> => {
	const response = await fetch(dirURL)
	const {status} = response
	if (status !== 200){
		throw new Error(`failed with status code ${status}`)
	}
	const html = await response.text()
	if (!html){
		throw new Error("html empty")
	}
	const fileURLs = [...html.matchAll(reFileURL)]
	if (!fileURLs.length){
		throw new Error("no file urls found")
	}
	return fileURLs.map(([,url]) => url)
}

export const scrapeDirectoryListing = async (dirURL: URL) : Promise<URL[]> => {
	const fileURLStrings = await getFileURLsFromDirectoryListing(dirURL)
	return fileURLStrings.map((fileURLStr: string) : URL => {
		const fileURL = new URL(fileURLStr, dirURL.origin)
		// if an absolute url is on the page, we must make sure it matches the directory origin
		// otherwise internal resources (LAN ips, etc.) could be accessed and possibly exploited!
		if (fileURL.origin !== dirURL.origin)
			throw new Error(`security error, file origin (${fileURL.origin}) != dir origin (${dirURL.origin})`)
		
		return fileURL
	})
}