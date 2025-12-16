# domains/server/couchdb/config-generator.nix
#
# Pure function to generate CouchDB local.ini configuration
# This is a helper function with no side effects, following Charter Section 10

{ adminUsername
, adminPassword
, maxDocumentSize
, maxHttpRequestSize
, corsOrigins
}:

''
[admins]
${adminUsername} = ${adminPassword}

[couchdb]
single_node=true
max_document_size = ${toString maxDocumentSize}

[chttpd]
require_valid_user = true
max_http_request_size = ${toString maxHttpRequestSize}

[chttpd_auth]
require_valid_user = true

[httpd]
WWW-Authenticate = Basic realm="couchdb"
enable_cors = true

[cors]
origins = ${builtins.concatStringsSep "," corsOrigins}
credentials = true
headers = accept, authorization, content-type, origin, referer
methods = GET, PUT, POST, HEAD, DELETE
max_age = 3600
''
