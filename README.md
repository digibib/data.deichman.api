# REST API for Deichman's RDF-store

## Endpoint
    http://data.deichman.no/api

The return format is JSON. All responses from /api/reviews and /api/works now responds to the format:

```
"works" : [
  { "uri" : "http://example.com/workid",
    "title" : "a title",
    "authors": [
      {
      "uri": "http://example.com/authorid",
      "name": Author's name",
      }
    ],
      ...
    "reviews" : [ 
      {
      "uri": "http://example.com/review_id",
      "title": "A Review Title",
      "reviewer": {
        "uri": "http://example.com/reviewer_id",
        "name": "Reviewer's name"
        },
      }
    ]
  }
]
         
```

## Available routes and HTTP methods
The API will be expanded as we see fit. Currently only the `/reviews` and `/works` endpoints are implemented.

The API is open for anyone to use, but a key is required in order to write to the API (i.e perform POST/PUT/DELETE requests). Please get in touch if your library wants to publish to our RDF-store.

## The Reviews Endpoint 

### Architecture

![API architecture](https://github.com/digibib/data.deichman.api/raw/develop/doc/review_rdf.png)


### GET /reviews

Fetches one or more reviews

#### Allowed parameters:   `reviewer`, `work`, `author`, `isbn`, `author_name`, `title`, `reviewer`, `source`
#### Filtering parameters: `order_by`, `order`, `limit`, `offset`, `published`, `cluster`

* Other parameters will be ignored if `uri`, `reviewer` or `work`  is present.
* The `uri` must refer to a bookreview. `uri` can also be an Array of uris
* `reviewer`, `work`, `author`, `reviewer`, and `source` must be a uri
* `offset` and `limit` must be integers.
* `order_by` allows values `author_name`, `title`, `reviewer``, `issued`, `modified`, `created` 
* `order` must be `desc` or `asc`.

Examples
```
http GET http://data.deichman.no/api/reviews uri="http://data.deichman.no/bookreviews/deich3456"
http GET http://data.deichman.no/api/reviews uri:='["http://data.deichman.no/bookreviews/deich3456",
                                                    "http://data.deichman.no/bookreviews/deich3457"]'
http GET http://data.deichman.no/api/reviews reviewer="http://data.deichman.no/reviewer/id_0"
http GET http://data.deichman.no/api/reviews work="http://data.deichman.no/work/x18370200_snoemannen"
http GET http://data.deichman.no/api/reviews limit=20 offset=20 order_by=author_name order=desc

```

### GET /works

Fetches one or more works, optionally with reviews

#### Allowed parameters: `uri`, `isbn`, `title`, `author`, `author_name`

* Other parameters will be ignored if `uri`or `isbn` is present.
* The `uri` must refer to a work id.
* `offset` and `limit` must be integers.
* `order_by` allows values `author_name`, `title`, `issued`, `modified`, `created` 
* `order` must be `desc` or `asc`.

Examples
```
http GET http://data.deichman.no/api/works uri="http://data.deichman.no/work/x18370200_snoemannen" reviews=true
http GET http://data.deichman.no/api/works uri:='["http://data.deichman.no/resource/work/x123456",
                                                    "http://data.deichman.no/resource/work/x123456"]'
http GET http://data.deichman.no/api/works title="Test Title"
http GET http://data.deichman.no/api/works author="Jo Nesbø" reviews=true limit=10 order_by=author_name order=desc
```

### POST /reviews

Creates a new review

#### Parameters

* Required: `api_key`, `isbn`, `title`, `teaser`, `text`
* Optional: `reviewer`, `audience`

    allowed audience values are `voksen`, `adult`, `ungdom`, `youth`, `children` or `barn`
    can be multiple separated by either comma, slash or pipe (,/|)    

Example
```
http POST http://data.deichman.no/api/reviews api_key="dummyapikey" isbn=9788243006218 title="Title of review"
    teaser="A brief text for teaser, infoscreens, etc." text="The entire text of review. Lorem ipsum and the glory of utf-8"
    reviewer="John Doe" audience="children"
```

### PUT /reviews

Updates existing review

#### Parameters

* Required: `api_key`, `uri`
* Optional: `isbn|title|teaser|text|reviewer|audience`


### DELETE /reviews

Deletes a review

#### Parameters

* Required:  `api_key`, `uri`

#### Returns

JSON hash result string
