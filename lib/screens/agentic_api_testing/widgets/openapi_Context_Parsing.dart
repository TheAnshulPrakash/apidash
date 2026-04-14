import 'dart:convert';

void main() {
  // for testing I've taken shop.json
  final String openApiRaw = r'''{
  "openapi": "3.1.0",
  "info": {
    "title": "Library Management System",
    "version": "0.1.0"
  },
  "paths": {
    "/token": {
      "post": {
        "summary": "Login",
        "operationId": "login_token_post",
        "requestBody": {
          "content": {
            "application/x-www-form-urlencoded": {
              "schema": {
                "$ref": "#/components/schemas/Body_login_token_post"
              }
            }
          },
          "required": true
        },
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {

                }
              }
            }
          },
          "422": {
            "description": "Validation Error",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/HTTPValidationError"
                }
              }
            }
          }
        }
      }
    },
    "/users/": {
      "post": {
        "summary": "Create User",
        "operationId": "create_user_users__post",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/UserCreate"
              }
            }
          },
          "required": true
        },
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {

                }
              }
            }
          },
          "422": {
            "description": "Validation Error",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/HTTPValidationError"
                }
              }
            }
          }
        }
      }
    },
    "/books/": {
      "get": {
        "summary": "Get Books",
        "operationId": "get_books_books__get",
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {
                  "items": {
                    "$ref": "#/components/schemas/BookResponse"
                  },
                  "type": "array",
                  "title": "Response Get Books Books  Get"
                }
              }
            }
          }
        }
      },
      "post": {
        "summary": "Add Book",
        "operationId": "add_book_books__post",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/BookBase"
              }
            }
          },
          "required": true
        },
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/BookResponse"
                }
              }
            }
          },
          "422": {
            "description": "Validation Error",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/HTTPValidationError"
                }
              }
            }
          }
        },
        "security": [
          {
            "OAuth2PasswordBearer": []
          }
        ]
      }
    },
    "/books/{book_id}": {
      "delete": {
        "summary": "Delete Book",
        "operationId": "delete_book_books__book_id__delete",
        "security": [
          {
            "OAuth2PasswordBearer": []
          }
        ],
        "parameters": [
          {
            "name": "book_id",
            "in": "path",
            "required": true,
            "schema": {
              "type": "integer",
              "title": "Book Id"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {

                }
              }
            }
          },
          "422": {
            "description": "Validation Error",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/HTTPValidationError"
                }
              }
            }
          }
        }
      }
    },
    "/books/{book_id}/borrow": {
      "post": {
        "summary": "Borrow Book",
        "operationId": "borrow_book_books__book_id__borrow_post",
        "security": [
          {
            "OAuth2PasswordBearer": []
          }
        ],
        "parameters": [
          {
            "name": "book_id",
            "in": "path",
            "required": true,
            "schema": {
              "type": "integer",
              "title": "Book Id"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Successful Response",
            "content": {
              "application/json": {
                "schema": {

                }
              }
            }
          },
          "422": {
            "description": "Validation Error",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/HTTPValidationError"
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Body_login_token_post": {
        "properties": {
          "grant_type": {
            "anyOf": [
              {
                "type": "string",
                "pattern": "password"
              },
              {
                "type": "null"
              }
            ],
            "title": "Grant Type"
          },
          "username": {
            "type": "string",
            "title": "Username"
          },
          "password": {
            "type": "string",
            "title": "Password"
          },
          "scope": {
            "type": "string",
            "title": "Scope",
            "default": ""
          },
          "client_id": {
            "anyOf": [
              {
                "type": "string"
              },
              {
                "type": "null"
              }
            ],
            "title": "Client Id"
          },
          "client_secret": {
            "anyOf": [
              {
                "type": "string"
              },
              {
                "type": "null"
              }
            ],
            "title": "Client Secret"
          }
        },
        "type": "object",
        "required": [
          "username",
          "password"
        ],
        "title": "Body_login_token_post"
      },
      "BookBase": {
        "properties": {
          "title": {
            "type": "string",
            "title": "Title"
          },
          "author": {
            "type": "string",
            "title": "Author"
          }
        },
        "type": "object",
        "required": [
          "title",
          "author"
        ],
        "title": "BookBase"
      },
      "BookResponse": {
        "properties": {
          "title": {
            "type": "string",
            "title": "Title"
          },
          "author": {
            "type": "string",
            "title": "Author"
          },
          "id": {
            "type": "integer",
            "title": "Id"
          },
          "is_borrowed": {
            "type": "boolean",
            "title": "Is Borrowed"
          }
        },
        "type": "object",
        "required": [
          "title",
          "author",
          "id",
          "is_borrowed"
        ],
        "title": "BookResponse"
      },
      "HTTPValidationError": {
        "properties": {
          "detail": {
            "items": {
              "$ref": "#/components/schemas/ValidationError"
            },
            "type": "array",
            "title": "Detail"
          }
        },
        "type": "object",
        "title": "HTTPValidationError"
      },
      "UserCreate": {
        "properties": {
          "username": {
            "type": "string",
            "title": "Username"
          },
          "password": {
            "type": "string",
            "title": "Password"
          }
        },
        "type": "object",
        "required": [
          "username",
          "password"
        ],
        "title": "UserCreate"
      },
      "ValidationError": {
        "properties": {
          "loc": {
            "items": {
              "anyOf": [
                {
                  "type": "string"
                },
                {
                  "type": "integer"
                }
              ]
            },
            "type": "array",
            "title": "Location"
          },
          "msg": {
            "type": "string",
            "title": "Message"
          },
          "type": {
            "type": "string",
            "title": "Error Type"
          }
        },
        "type": "object",
        "required": [
          "loc",
          "msg",
          "type"
        ],
        "title": "ValidationError"
      }
    },
    "securitySchemes": {
      "OAuth2PasswordBearer": {
        "type": "oauth2",
        "flows": {
          "password": {
            "scopes": {

            },
            "tokenUrl": "token"
          }
        }
      }
    }
  }
}''';

  final Map<String, dynamic> spec = jsonDecode(openApiRaw);
  final Map<String, dynamic> allPaths = spec['paths'] ?? {};
  final Map<String, dynamic> allSchemas = spec['components']?['schemas'] ?? {};

  final Map<String, Map<String, dynamic>> featureBatches = {};

  allPaths.forEach((pathKey, pathData) {
    final segments = pathKey.split('/').where((s) => s.isNotEmpty).toList();
    final String label = segments.isEmpty ? 'root' : segments.first;

    if (!featureBatches.containsKey(label)) {
      featureBatches[label] = {
        "openapi": spec['openapi'],
        "info": spec['info'],
        "paths": <String, dynamic>{},
        "components": {"schemas": <String, dynamic>{}}
      };
    }
    featureBatches[label]!['paths'][pathKey] = pathData;

    final Set<String> refsFound = {};
    recursiveFindRefs(pathData, refsFound);

    for (var ref in refsFound) {
      final schemaName = ref.split('/').last;
      if (allSchemas.containsKey(schemaName)) {
        featureBatches[label]!['components']['schemas'][schemaName] =
            allSchemas[schemaName];

        final Set<String> nestedRefs = {};
        recursiveFindRefs(allSchemas[schemaName], nestedRefs);
        for (var nRef in nestedRefs) {
          final nName = nRef.split('/').last;
          featureBatches[label]!['components']['schemas'][nName] =
              allSchemas[nName];
        }
      }
    }
  });

  featureBatches.forEach((key, value) {
    print('DOMAIN: ${key.toUpperCase()} ---');
    print(JsonEncoder.withIndent('  ').convert(value));
    print('\n');
  });
}

void recursiveFindRefs(dynamic node, Set<String> refs) {
  if (node is Map) {
    if (node.containsKey('\$ref')) {
      refs.add(node['\$ref'] as String);
    }
    node.forEach((_, value) => recursiveFindRefs(value, refs));
  } else if (node is List) {
    for (var element in node) {
      recursiveFindRefs(element, refs);
    }
  }
}
