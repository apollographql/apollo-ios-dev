use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// A configuration object that defines behavior for schema download.
/// Data-only -- no network logic, no HTTP client, no async downloading.
///
/// Mirrors Swift's `ApolloSchemaDownloadConfiguration` struct.
#[derive(Debug, Clone, PartialEq)]
pub struct ApolloSchemaDownloadConfiguration {
  /// How to download your schema. Supports the Apollo Registry and GraphQL Introspection methods.
  pub download_method: DownloadMethod,
  /// The maximum time (in seconds) to wait before indicating that the download timed out.
  /// Defaults to 30.0 seconds.
  pub download_timeout: f64,
  /// Any additional HTTP headers to include when retrieving your schema.
  pub headers: Vec<HTTPHeader>,
  /// The local path where the downloaded schema should be written to.
  pub output_path: String,
}

/// How to attempt to download your schema.
///
/// Mirrors Swift's `ApolloSchemaDownloadConfiguration.DownloadMethod` enum.
#[derive(Debug, Clone, PartialEq)]
pub enum DownloadMethod {
  /// GraphQL Introspection connecting to the specified URL.
  Introspection {
    endpoint_url: String,
    http_method: HTTPMethod,
    output_format: OutputFormat,
    include_deprecated_input_values: bool,
  },
  /// The Apollo Schema Registry.
  ApolloRegistry {
    api_key: String,
    graph_id: String,
    variant: String,
  },
}

/// The HTTP request method for introspection downloads.
///
/// Mirrors Swift's `ApolloSchemaDownloadConfiguration.DownloadMethod.HTTPMethod` enum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HTTPMethod {
  /// Use POST for HTTP requests. This is the default for GraphQL.
  Post,
  /// Use GET for HTTP requests with the GraphQL query being sent in the query string parameter.
  Get { query_parameter_name: String },
}

/// The output format for the downloaded schema.
///
/// Mirrors Swift's `ApolloSchemaDownloadConfiguration.DownloadMethod.OutputFormat` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OutputFormat {
  /// A Schema Definition Language (SDL) document.
  SDL,
  /// A JSON schema definition provided as the result of a schema introspection query.
  JSON,
}

/// An HTTP header that will be sent in the schema download request.
///
/// Mirrors Swift's `ApolloSchemaDownloadConfiguration.HTTPHeader` struct.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HTTPHeader {
  /// The name of the header field.
  pub key: String,
  /// The value for the header field.
  pub value: String,
}

// -- Custom serde for DownloadMethod --

impl<'de> Deserialize<'de> for DownloadMethod {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct DownloadMethodVisitor;

    impl<'de> Visitor<'de> for DownloadMethodVisitor {
      type Value = DownloadMethod;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("a DownloadMethod object with one key: introspection or apolloRegistry")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let key: String = map
          .next_key()?
          .ok_or_else(|| de::Error::custom("Invalid number of keys found, expected one."))?;

        match key.as_str() {
          "introspection" => {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct Inner {
              #[serde(rename = "endpointURL")]
              endpoint_url: String,
              #[serde(default = "default_http_method")]
              http_method: HTTPMethod,
              #[serde(default = "default_output_format")]
              output_format: OutputFormat,
              #[serde(default)]
              include_deprecated_input_values: bool,
            }
            fn default_http_method() -> HTTPMethod {
              HTTPMethod::Post
            }
            fn default_output_format() -> OutputFormat {
              OutputFormat::SDL
            }
            let inner: Inner = map.next_value()?;
            Ok(DownloadMethod::Introspection {
              endpoint_url: inner.endpoint_url,
              http_method: inner.http_method,
              output_format: inner.output_format,
              include_deprecated_input_values: inner.include_deprecated_input_values,
            })
          }
          "apolloRegistry" => {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct Inner {
              #[serde(rename = "apiKey")]
              api_key: String,
              #[serde(rename = "graphID")]
              graph_id: String,
              #[serde(default = "default_variant")]
              variant: String,
            }
            fn default_variant() -> String {
              "current".to_string()
            }
            let inner: Inner = map.next_value()?;
            Ok(DownloadMethod::ApolloRegistry {
              api_key: inner.api_key,
              graph_id: inner.graph_id,
              variant: inner.variant,
            })
          }
          other => Err(de::Error::unknown_variant(
            other,
            &["introspection", "apolloRegistry"],
          )),
        }
      }
    }

    deserializer.deserialize_map(DownloadMethodVisitor)
  }
}

impl Serialize for DownloadMethod {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    match self {
      DownloadMethod::Introspection {
        endpoint_url,
        http_method,
        output_format,
        include_deprecated_input_values,
      } => {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Inner<'a> {
          #[serde(rename = "endpointURL")]
          endpoint_url: &'a str,
          http_method: &'a HTTPMethod,
          output_format: &'a OutputFormat,
          include_deprecated_input_values: bool,
        }
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry(
          "introspection",
          &Inner {
            endpoint_url,
            http_method,
            output_format,
            include_deprecated_input_values: *include_deprecated_input_values,
          },
        )?;
        map.end()
      }
      DownloadMethod::ApolloRegistry {
        api_key,
        graph_id,
        variant,
      } => {
        #[derive(Serialize)]
        struct Inner<'a> {
          #[serde(rename = "apiKey")]
          api_key: &'a str,
          #[serde(rename = "graphID")]
          graph_id: &'a str,
          variant: &'a str,
        }
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry(
          "apolloRegistry",
          &Inner {
            api_key,
            graph_id,
            variant,
          },
        )?;
        map.end()
      }
    }
  }
}

// -- Custom serde for HTTPMethod --

impl<'de> Deserialize<'de> for HTTPMethod {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct HTTPMethodVisitor;

    impl<'de> Visitor<'de> for HTTPMethodVisitor {
      type Value = HTTPMethod;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("an HTTPMethod object with one key: POST or GET")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let key: String = map
          .next_key()?
          .ok_or_else(|| de::Error::custom("Invalid number of keys found, expected one."))?;

        match key.as_str() {
          "POST" => {
            let _: serde_json::Value = map.next_value()?;
            Ok(HTTPMethod::Post)
          }
          "GET" => {
            #[derive(Deserialize)]
            struct Inner {
              #[serde(rename = "queryParameterName", default = "default_query_param")]
              query_parameter_name: String,
            }
            fn default_query_param() -> String {
              "query".to_string()
            }
            let inner: Inner = map.next_value()?;
            Ok(HTTPMethod::Get {
              query_parameter_name: inner.query_parameter_name,
            })
          }
          other => Err(de::Error::unknown_variant(other, &["POST", "GET"])),
        }
      }
    }

    deserializer.deserialize_map(HTTPMethodVisitor)
  }
}

impl Serialize for HTTPMethod {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    match self {
      HTTPMethod::Post => {
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry("POST", &serde_json::Map::new())?;
        map.end()
      }
      HTTPMethod::Get {
        query_parameter_name,
      } => {
        #[derive(Serialize)]
        struct Inner<'a> {
          #[serde(rename = "queryParameterName")]
          query_parameter_name: &'a str,
        }
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry(
          "GET",
          &Inner {
            query_parameter_name,
          },
        )?;
        map.end()
      }
    }
  }
}

// -- Custom serde for ApolloSchemaDownloadConfiguration --

impl<'de> Deserialize<'de> for ApolloSchemaDownloadConfiguration {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Helper {
      download_method: DownloadMethod,
      #[serde(default = "default_download_timeout")]
      download_timeout: f64,
      #[serde(default)]
      headers: serde_json::Value,
      output_path: String,
    }

    fn default_download_timeout() -> f64 {
      30.0
    }

    let helper = Helper::deserialize(deserializer)?;

    // Decode headers with dual-format support: array-of-structs or dictionary
    let headers = decode_headers(&helper.headers).map_err(de::Error::custom)?;

    Ok(ApolloSchemaDownloadConfiguration {
      download_method: helper.download_method,
      download_timeout: helper.download_timeout,
      headers,
      output_path: helper.output_path,
    })
  }
}

fn decode_headers(value: &serde_json::Value) -> Result<Vec<HTTPHeader>, String> {
  match value {
    serde_json::Value::Null => Ok(vec![]),
    serde_json::Value::Array(arr) => {
      // Try as array of HTTPHeader structs
      let mut headers = Vec::new();
      for item in arr {
        let header: HTTPHeader =
          serde_json::from_value(item.clone()).map_err(|e| e.to_string())?;
        headers.push(header);
      }
      Ok(headers)
    }
    serde_json::Value::Object(obj) => {
      // Dictionary format: convert to sorted array
      let mut headers: Vec<HTTPHeader> = obj
        .iter()
        .map(|(k, v)| HTTPHeader {
          key: k.clone(),
          value: v.as_str().unwrap_or("").to_string(),
        })
        .collect();
      headers.sort_by(|a, b| a.key.cmp(&b.key));
      Ok(headers)
    }
    _ => Ok(vec![]),
  }
}

impl Serialize for ApolloSchemaDownloadConfiguration {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    let mut map = serializer.serialize_map(Some(4))?;
    map.serialize_entry("downloadMethod", &self.download_method)?;
    map.serialize_entry("downloadTimeout", &self.download_timeout)?;
    map.serialize_entry("headers", &self.headers)?;
    map.serialize_entry("outputPath", &self.output_path)?;
    map.end()
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_download_method_introspection_roundtrip() {
    let json = r#"{"introspection":{"endpointURL":"http://server.com","httpMethod":{"POST":{}},"outputFormat":"SDL","includeDeprecatedInputValues":true}}"#;
    let parsed: DownloadMethod = serde_json::from_str(json).unwrap();
    assert!(matches!(parsed, DownloadMethod::Introspection { .. }));
    if let DownloadMethod::Introspection {
      endpoint_url,
      http_method,
      output_format,
      include_deprecated_input_values,
    } = &parsed
    {
      assert_eq!(endpoint_url, "http://server.com");
      assert_eq!(*http_method, HTTPMethod::Post);
      assert_eq!(*output_format, OutputFormat::SDL);
      assert!(*include_deprecated_input_values);
    }
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_download_method_apollo_registry_roundtrip() {
    let json = r#"{"apolloRegistry":{"apiKey":"ABC123","graphID":"DEF456","variant":"final"}}"#;
    let parsed: DownloadMethod = serde_json::from_str(json).unwrap();
    assert!(matches!(parsed, DownloadMethod::ApolloRegistry { .. }));
    if let DownloadMethod::ApolloRegistry {
      api_key,
      graph_id,
      variant,
    } = &parsed
    {
      assert_eq!(api_key, "ABC123");
      assert_eq!(graph_id, "DEF456");
      assert_eq!(variant, "final");
    }
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_apollo_registry_default_variant() {
    let json = r#"{"apolloRegistry":{"apiKey":"key","graphID":"id"}}"#;
    let parsed: DownloadMethod = serde_json::from_str(json).unwrap();
    if let DownloadMethod::ApolloRegistry { variant, .. } = &parsed {
      assert_eq!(variant, "current");
    } else {
      panic!("Expected ApolloRegistry variant");
    }
  }

  #[test]
  fn test_http_method_post_roundtrip() {
    let json = r#"{"POST":{}}"#;
    let parsed: HTTPMethod = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, HTTPMethod::Post);
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_http_method_get_roundtrip() {
    let json = r#"{"GET":{"queryParameterName":"MyQuery"}}"#;
    let parsed: HTTPMethod = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      HTTPMethod::Get {
        query_parameter_name: "MyQuery".to_string()
      }
    );
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_http_method_get_default_query_param() {
    let json = r#"{"GET":{}}"#;
    let parsed: HTTPMethod = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      HTTPMethod::Get {
        query_parameter_name: "query".to_string()
      }
    );
  }

  #[test]
  fn test_headers_array_format() {
    let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://x.com"}},"headers":[{"key":"Auth","value":"Bearer token"}],"outputPath":"schema.graphqls"}"#;
    let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(parsed.headers.len(), 1);
    assert_eq!(parsed.headers[0].key, "Auth");
    assert_eq!(parsed.headers[0].value, "Bearer token");
  }

  #[test]
  fn test_headers_dictionary_format() {
    let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://x.com"}},"headers":{"Authorization":"Bearer token","X-Custom":"value"},"outputPath":"schema.graphqls"}"#;
    let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();
    assert_eq!(parsed.headers.len(), 2);
    // Dictionary format is sorted by key
    assert_eq!(parsed.headers[0].key, "Authorization");
    assert_eq!(parsed.headers[1].key, "X-Custom");
  }

  #[test]
  fn test_schema_download_default_timeout() {
    let json = r#"{"downloadMethod":{"introspection":{"endpointURL":"http://x.com"}},"outputPath":"schema.graphqls"}"#;
    let parsed: ApolloSchemaDownloadConfiguration = serde_json::from_str(json).unwrap();
    assert!((parsed.download_timeout - 30.0).abs() < f64::EPSILON);
    assert!(parsed.headers.is_empty());
  }

  #[test]
  fn test_output_format_roundtrip() {
    let json = r#""SDL""#;
    let parsed: OutputFormat = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, OutputFormat::SDL);

    let json = r#""JSON""#;
    let parsed: OutputFormat = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, OutputFormat::JSON);
  }
}
