Part 1)
	HTTP(S) does not know the concept of a directory listing, there is no HTTP(S) method for listing files
	Thus, if we use HTTP(S), we must scrape using regular expressions (more performant / less robust) or DOM parsing (less performant / more robust)

	We first search if the U.S. Bureau of Labor Statistics has any other data interfaces
	We find https://www.bls.gov/bls/blsftp.htm (FTP interface)

	ftp.bls.gov DNS does not seem to resolve. Why?
	FTP was discontinued on March 1st 2014 [1,2]
	[1] https://www.bls.gov/bls/web_systems_update.htm
	[2] https://www.bls.gov/bls/discontinuation_ftp.htm/

	HTTPS is used instead of HTTP as it is more secure than HTTP.
	We use npm package undici, the fastest performing http client
	Carefully written regular expressions are used to scrape the filenames from the directory listing
	** TODO: Incremental Improvement: Recursive scrape for nested directories


	Both E-Tag header and Last-Modified header are used for checking if our S3 version of a file is outdated
	https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/If-None-Match
	If-None-Match is preferred to timestamps, because it is based on ETags which are usually the hash of file contents.

	Unfortunately, the gov HTTP server is NON-STANDARD and ignores If-None-Match request header
	Many hours were wasted attempting to figure out what I may have been doing wrong.

	curl includes e-tag options natively, instead of having to use the -H, --Header option.
	Even curl receives a 200 response status instead of a 304 (Not Modified) when issued with native e-tag commands:
		curl --etag-save etag.txt https://download.bls.gov/pub/time.series/pr/pr.footnote -v
		cat etag.txt
		curl --etag-compare etag.txt https://download.bls.gov/pub/time.series/pr/pr.footnote -v

	Luckily, this government server still handles If-Modified-Since properly, so 1/2 of our caching mechanisms suffice.

	[Gotchas]
		TypeScript's official compiler (tsc) renames all ts files to js
		https://github.com/microsoft/TypeScript/issues/40878
		https://github.com/microsoft/TypeScript/pull/44501#ref-issue-713122066
		(^ mentioned as recent as 2 days ago)

		This is a problem if we import from './file' instead of './file.js'
		Though it is inelegant, we have few local imports, so we opted to use the './file.js' pathing

		In larger projects, to get around this inelegance and refusal of TypeScript devs to improve tsc behavior, we can use Webpack, Rollup, Browserify, etc instead of TSC directly. 
		Or we can add an additional build step that renames the compiled file extensions.
		

	


	
# rearc-data-quest
