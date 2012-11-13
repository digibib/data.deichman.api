# REST API for Deichman's RDF-store

## Endpoint
    http://data.deichman.no/api

The return format is JSON.

## Available routes and HTTP methods
The API will be expanded as we see fit. Currently only the `/reviews` endpoint is implemented.

The API is open for anyone to use, but a key is required in order to write to the API (i.e perform POST/PUT/DELETE requests). Please get in tocuh if your library wants to publish to our RDF-store.

### GET /reviews
Parameters: `isbn`, `uri`, `author`, `title`

Other parameters will be ignored if `isbn` or `uri` is present.
The `uri` must refer to a bookreview.

Examples
```
http GET http://data.deichman.no/api/v1/reviews isbn=9788243006218
http GET http://data.deichman.no/api/v1/reviews author="Knut Hamsun" title="Sult"
http GET http://data.deichman.no/api/v1/reviews author="Nesbø, Jo"
http GET http://data.deichman.no/api/v1/reviews uri="http://data.deichman.no/bookreviews/deich3456"
```
#### Returns

JSON hash of one or more `work`, and an array of its `reviews`

### POST /reviews

#### Parameters

* Required: `api_key`, `isbn`, `title`, `teaser`, `text`
* Optional: `reviewer`, `audience`, `source`

Example
```
http POST http://data.deichman.no/api/v1/reviews api_key="dummyapikey" isbn=9788243006218 title="Title of review"
    teaser="A brief text for teaser, infoscreens, etc." text="The entire text of review. Lorem ipsum and the glory of utf-8"
    reviewer="John Doe" audience="Children"
```

#### Returns

JSON hash of one or more `work`, its `reviews` and `uri` of review

### PUT /reviews

Updates existing review

#### Parameters

* Required: `api_key`, `uri`
* Optional: `isbn|title|teaser|text|reviewer|audience|source`

#### Returns

JSON hash of modified review, `before` and `after`

### DELETE /reviews

#### Parameters

* Required:  `api_key`, `uri`

#### Returns

JSON hash success/failure (boolean)
