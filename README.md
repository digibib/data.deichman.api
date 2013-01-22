# REST API for Deichman's RDF-store

## Endpoint
    http://data.deichman.no/api

The return format is JSON.

## Available routes and HTTP methods
The API will be expanded as we see fit. Currently only the `/reviews` endpoint is implemented.

The API is open for anyone to use, but a key is required in order to write to the API (i.e perform POST/PUT/DELETE requests). Please get in tocuh if your library wants to publish to our RDF-store.

### Architecture

![API architecture](https://github.com/digibib/data.deichman.api/raw/develop/doc/review_rdf.png)


### GET /reviews

Fetches one or more reviews

#### Parameters: `isbn`, `uri`, `author`, `title`, `reviewer`, `work`

Other parameters will be ignored if `isbn`, `uri`, `reviewer` or `work`  is present.
The `uri` must refer to a bookreview.

Examples
```
http GET http://data.deichman.no/api/reviews isbn=9788243006218
http GET http://data.deichman.no/api/reviews author="Knut Hamsun" title="Sult"
http GET http://data.deichman.no/api/reviews author="Nesbø, Jo"
http GET http://data.deichman.no/api/reviews uri="http://data.deichman.no/bookreviews/deich3456"
http GET http://data.deichman.no/api/reviews reviewer="Test Reviewer"
http GET http://data.deichman.no/api/reviews work="http://data.deichman.no/work/x18370200_snoemannen"
```
#### Returns

JSON hash of one or more `work`, and an array of its `reviews`

### POST /reviews

Creates a new review

#### Parameters

* Required: `api_key`, `isbn`, `title`, `teaser`, `text`
* Optional: `reviewer`, `audience`

    allowed audience values are `voksen|adult`, `ungdom|youth`, `children|barn`
    can be multiple separated by either comma, slash or pipe (,/|)    

Example
```
http POST http://data.deichman.no/api/reviews api_key="dummyapikey" isbn=9788243006218 title="Title of review"
    teaser="A brief text for teaser, infoscreens, etc." text="The entire text of review. Lorem ipsum and the glory of utf-8"
    reviewer="John Doe" audience="children"
```

#### Returns

* JSON hash of one or more `work`, its `reviews` and `uri` of review
* if new reviewer:      reviewer ID (created unique in database as Reviewer and UserAccount
* if existing reviewer: reviewer name

### PUT /reviews

Updates existing review

#### Parameters

* Required: `api_key`, `uri`
* Optional: `isbn|title|teaser|text|reviewer|audience`

#### Returns

JSON hash of modified review, `before` and `after`

### DELETE /reviews

Deletes a review

#### Parameters

* Required:  `api_key`, `uri`

#### Returns

JSON hash success/failure (boolean)
