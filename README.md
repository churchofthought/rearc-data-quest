# rearc-data-quest

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
		Lambda only supports CommonJS entry point
		We have to configure TypeScript via tsconfig.json with these settings because of that:
			"module": "CommonJS",
			"allowSyntheticDefaultImports": true,
			"esModuleInterop": true,
		
		undici has incorporated undici-fetch, but only for Node >= v16.
		https://github.com/nodejs/undici/blob/727ba62fa05b97b5cfd380b92cf94f7043de8d05/index.js#L91
		AWS only supports Node v14.x out of the box.
		We'd need to use Docker if we wanted to use a custom Node build.
		I forked undici and used a polyfill of AbortController and ReadableStream to allow for use on Node v14
		https://github.com/churchofthought/undici/
		This failed so I ended up using node-fetch, but this package doesn't work with CommonJS,
		so I used a CJS stub someone else created

		AWS SDK v3 is very poorly documented and has deranged errors when S3Client is reused.
		Errors with no message or code with 400 status.
		This is fixed when a new S3Client is used for each individual request.
		A memory hog but the only way to fix the issue.

	[TODO Improvements]
		JSDoc Comments on all methods, parameters, and return values
		Unit & Integration Tests (in Mocha, Tap, etc.) 
			Code written as isolated pure functions.
			Mock testing & Dependency injection
		Request multiplexing, so we aren't just waiting on 1 request in isolation
			This speed up our entire end-to-end process.
			Promise.all is naive and dangerous, a parallelMap or parallelDo with a concurrency limit (n=10 for instance) is safer
			ie. https://gist.github.com/churchofthought/b1a937929de44afb322ab850b4a3f169
			( some npm modules do exist for this but are for more complex than they need to be )
		HTTP/2 supported library to allow for native pipelining of requests and responses
		https://en.wikipedia.org/wiki/HTTP/2

Part 2)
	This part was relatively easy to do using the HTTP and S3 methods written in Part 1
	Because we want this Part 2 API JSON file to not be deleted by the S3 Sync in Part 1, we added an ignoreFiles parameter to Part 1's sync stage.
	
	[Gotchas]
		Part 1 might have a file with the same name as the key we store the JSON for API call of Part 2.
		This is highly unlikely but still worth mentioning. We can be resilient to it by using a sub-folder.
	
Part 3)
	s3fs is used to read the s3 files streaming-wise with panda
	Python & Pandas DataFrames were used for ease of use.
	If the data scale were larger, we might use a different technology such as Spark.
	
	The ipynb notebook shows all the queries done.
	The queries were done in a way that is easy to understand.

Part 4)
	Many python dependencies like Pandas are compiled for the platform specifically.
	I wanted to render both an executed ipynb and web-viewable HTML document every time the two files used for analysis changed.
	I used Docker to create the AWS Python 3.9 environment so I could install all the dependencies necessary to re-execute the ipynb notebook, render it to HTML, and also interact with s3.
	By using pip install jupyter nbconvert pandas -t /tmp/modules, along with docker cp, I was able to pull the modules into my host OS

	I used lambda layers to avoid having to republish the python modules every time we want to change the main code
	Layer size limits (250MB unpacked) meant I had to break up the dependencies into two layers.

	[TODO Improvements]
		Testing & error checking
		Automation of lambda layer creation (docker + pip + chunking into layers)