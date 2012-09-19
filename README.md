# REST API for Deichman's RDF-store

## Endpoint
    http://data.deichman.no/api/v1
The API is versioned, as specified in the URL. The current version is v1.

## Available routes and HTTP methods
The API will be expanded as we see fit. Currently only the `/reviews` endpoint is implemented.

The API is open for anyone to use, but a key is required in order to write to the API (i.e perform POST/PUT/DELETE requests). Please get in tocuh if your library wants to publish to our graph.

The return format is JSON.

* GET /reviews
Parameters: `ISBN`, `URI`, `Author`, `Title` 

Other parameters will be ignored if `ISBN` or `URI` is present.

* POST /reviews
Parameters: `ISBN`, `ID`, `Author`, `Title`, `Source`

* PUT /reviews
Parameters: `ISBN`, `URI`, `Author`, `Title`,  `Source`

* DELETE /reviews
Parameters: `URI`