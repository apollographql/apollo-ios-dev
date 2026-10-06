use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::access_modifier::AccessModifier;

// MARK: - ApolloSDKDependency

/// Configuration for the apollo-ios dependency in SPM modules.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType.ApolloSDKDependency`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApolloSDKDependency {
    /// URL for the SPM package dependency. Defaults to the apollo-ios GitHub repository.
    pub url: String,
    /// Type of SPM dependency to use.
    pub sdk_version: SDKVersion,
}

impl Default for ApolloSDKDependency {
    fn default() -> Self {
        Self {
            url: "https://github.com/apollographql/apollo-ios".to_string(),
            sdk_version: SDKVersion::Default,
        }
    }
}

impl ApolloSDKDependency {
    /// Renders the Swift Package.swift dependency declaration string.
    ///
    /// Mirrors Swift's `ApolloSDKDependency.dependencyString` computed property.
    pub fn dependency_string(&self, codegen_version: &str) -> String {
        match &self.sdk_version {
            SDKVersion::Default => {
                format!(".package(url: \"{}\", exact: \"{}\")", self.url, codegen_version)
            }
            SDKVersion::Branch { name } => {
                format!(".package(url: \"{}\", branch: \"{}\")", self.url, name)
            }
            SDKVersion::Commit { hash } => {
                format!(".package(url: \"{}\", revision: \"{}\")", self.url, hash)
            }
            SDKVersion::Exact { version } => {
                format!(".package(url: \"{}\", exact: \"{}\")", self.url, version)
            }
            SDKVersion::From { version } => {
                format!(".package(url: \"{}\", from: \"{}\")", self.url, version)
            }
            SDKVersion::Local { path } => {
                format!(".package(name: \"apollo-ios\", path: \"{}\")", path)
            }
        }
    }
}

impl<'de> Deserialize<'de> for ApolloSDKDependency {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        struct Helper {
            #[serde(default = "default_apollo_url")]
            url: String,
            #[serde(rename = "sdkVersion", default)]
            sdk_version: SDKVersionHelper,
        }

        fn default_apollo_url() -> String {
            "https://github.com/apollographql/apollo-ios".to_string()
        }

        let helper = Helper::deserialize(deserializer)?;
        Ok(ApolloSDKDependency {
            url: helper.url,
            sdk_version: helper.sdk_version.into(),
        })
    }
}

impl Serialize for ApolloSDKDependency {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        let mut state = serializer.serialize_struct("ApolloSDKDependency", 2)?;
        state.serialize_field("url", &self.url)?;
        match &self.sdk_version {
            SDKVersion::Default => {
                state.serialize_field("sdkVersion", "default")?;
            }
            _ => {
                state.serialize_field("sdkVersion", &self.sdk_version)?;
            }
        }
        state.end()
    }
}

/// Type of SPM dependency version specification.
///
/// Mirrors Swift's `ApolloSDKDependency.SDKVersion` enum.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SDKVersion {
    /// Uses the exact codegen library version.
    #[serde(rename = "default")]
    Default,
    /// Uses a specific branch name.
    #[serde(rename = "branch")]
    Branch { name: String },
    /// Uses a specific commit hash.
    #[serde(rename = "commit")]
    Commit { hash: String },
    /// Uses an exact version string.
    #[serde(rename = "exact")]
    Exact { version: String },
    /// Uses a minimum version ("from" semver range).
    #[serde(rename = "from")]
    From { version: String },
    /// Uses a local file path.
    #[serde(rename = "local")]
    Local { path: String },
}

impl Default for SDKVersion {
    fn default() -> Self {
        Self::Default
    }
}

/// Internal helper for deserializing SDKVersion which can be either a string ("default")
/// or a tagged enum.
#[derive(Deserialize)]
#[serde(untagged)]
enum SDKVersionHelper {
    String(String),
    Tagged(SDKVersion),
}

impl Default for SDKVersionHelper {
    fn default() -> Self {
        SDKVersionHelper::String("default".to_string())
    }
}

impl From<SDKVersionHelper> for SDKVersion {
    fn from(helper: SDKVersionHelper) -> Self {
        match helper {
            SDKVersionHelper::String(s) if s == "default" => SDKVersion::Default,
            SDKVersionHelper::String(_) => SDKVersion::Default,
            SDKVersionHelper::Tagged(v) => v,
        }
    }
}

// MARK: - ModuleType

/// Compatible dependency manager automation.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.SchemaTypesFileOutput.ModuleType` enum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ModuleType {
  /// Generated schema types will be manually embedded in a target with the specified `name`.
  /// No module will be created for the generated schema types. `access_modifier` defaults
  /// to `Internal`.
  EmbeddedInTarget {
    name: String,
    access_modifier: AccessModifier,
  },
  /// Generates a `Package.swift` file suitable for linking via Swift Package Manager.
  /// Generated schema types will be packaged in a Swift Package Manager module,
  /// depending on apollo-ios as described by `apollo_sdk_dependency`.
  ///
  /// Mirrors Swift's `.swiftPackage(apolloSDKDependency:)`; the deprecated
  /// `swiftPackageManager` key decodes to this with the default dependency.
  SwiftPackage {
    apollo_sdk_dependency: ApolloSDKDependency,
  },
  /// No module will be created. You must create the module to support your preferred
  /// dependency manager (e.g., CocoaPods).
  Other,
}

impl ModuleType {
    /// Returns the `ApolloSDKDependency` if this is a SwiftPackageManager module type.
    /// For backward compatibility, returns the default dependency when the config
    /// did not include explicit SDK dependency settings.
    pub fn apollo_sdk_dependency(&self) -> Option<ApolloSDKDependency> {
        match self {
            ModuleType::SwiftPackage { apollo_sdk_dependency } => Some(apollo_sdk_dependency.clone()),
            _ => None,
        }
    }
}

impl<'de> Deserialize<'de> for ModuleType {
  fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
    struct ModuleTypeVisitor;

    impl<'de> Visitor<'de> for ModuleTypeVisitor {
      type Value = ModuleType;

      fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.write_str("a ModuleType object with one key: embeddedInTarget, swiftPackage, swiftPackageManager, or other")
      }

      fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
        let key: String = map
          .next_key()?
          .ok_or_else(|| de::Error::custom("Invalid number of keys found, expected one."))?;

        match key.as_str() {
          "embeddedInTarget" => {
            #[derive(Deserialize)]
            struct Inner {
              name: String,
              #[serde(rename = "accessModifier", default = "crate::config::access_modifier::default_internal")]
              access_modifier: AccessModifier,
            }
            let inner: Inner = map.next_value()?;
            Ok(ModuleType::EmbeddedInTarget {
              name: inner.name,
              access_modifier: inner.access_modifier,
            })
          }
          "swiftPackageManager" => {
            let _: serde_json::Value = map.next_value()?;
            Ok(ModuleType::SwiftPackage {
              apollo_sdk_dependency: ApolloSDKDependency::default(),
            })
          }
          "swiftPackage" => {
            #[derive(Deserialize)]
            struct Inner {
              #[serde(rename = "apolloSDKDependency", default)]
              apollo_sdk_dependency: ApolloSDKDependency,
            }
            let inner: Inner = map.next_value()?;
            Ok(ModuleType::SwiftPackage {
              apollo_sdk_dependency: inner.apollo_sdk_dependency,
            })
          }
          "other" => {
            let _: serde_json::Value = map.next_value()?;
            Ok(ModuleType::Other)
          }
          other => Err(de::Error::unknown_variant(
            other,
            &["embeddedInTarget", "swiftPackage", "swiftPackageManager", "other"],
          )),
        }
      }
    }

    deserializer.deserialize_map(ModuleTypeVisitor)
  }
}

impl Serialize for ModuleType {
  fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
    match self {
      ModuleType::EmbeddedInTarget {
        name,
        access_modifier,
      } => {
        #[derive(Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Inner<'a> {
          name: &'a str,
          access_modifier: &'a AccessModifier,
        }
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry(
          "embeddedInTarget",
          &Inner {
            name,
            access_modifier,
          },
        )?;
        map.end()
      }
      ModuleType::SwiftPackage { apollo_sdk_dependency } => {
        #[derive(Serialize)]
        struct Inner<'a> {
          // Swift's `SwiftPackageCodingKeys.apolloSDKDependency`
          #[serde(rename = "apolloSDKDependency")]
          apollo_sdk_dependency: &'a ApolloSDKDependency,
        }
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry("swiftPackage", &Inner { apollo_sdk_dependency })?;
        map.end()
      }
      ModuleType::Other => {
        let mut map = serializer.serialize_map(Some(1))?;
        map.serialize_entry("other", &serde_json::Map::new())?;
        map.end()
      }
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_module_type_embedded_in_target_roundtrip() {
    let json = r#"{"embeddedInTarget":{"name":"SomeTarget","accessModifier":"public"}}"#;
    let parsed: ModuleType = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      ModuleType::EmbeddedInTarget {
        name: "SomeTarget".to_string(),
        access_modifier: AccessModifier::Public,
      }
    );
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_module_type_embedded_default_access_modifier() {
    let json = r#"{"embeddedInTarget":{"name":"MyTarget"}}"#;
    let parsed: ModuleType = serde_json::from_str(json).unwrap();
    assert_eq!(
      parsed,
      ModuleType::EmbeddedInTarget {
        name: "MyTarget".to_string(),
        access_modifier: AccessModifier::Internal,
      }
    );
  }

  /// Since 1.16.0 the deprecated `swiftPackageManager` key decodes to
  /// `.swiftPackage(apolloSDKDependency: .default)` and is encoded in that form (Swift's
  /// `ModuleType.init(from:)` / `ApolloSDKDependency.encode(to:)`).
  #[test]
  fn test_module_type_swift_package_manager_roundtrip() {
    let json = r#"{"swiftPackageManager":{}}"#;
    let parsed: ModuleType = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, ModuleType::SwiftPackage { apollo_sdk_dependency: ApolloSDKDependency::default() });
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(
      serialized,
      r#"{"swiftPackage":{"apolloSDKDependency":{"url":"https://github.com/apollographql/apollo-ios","sdkVersion":"default"}}}"#
    );
  }

  #[test]
  fn test_module_type_other_roundtrip() {
    let json = r#"{"other":{}}"#;
    let parsed: ModuleType = serde_json::from_str(json).unwrap();
    assert_eq!(parsed, ModuleType::Other);
    let serialized = serde_json::to_string(&parsed).unwrap();
    assert_eq!(serialized, json);
  }

  #[test]
  fn test_module_type_unknown_variant_error() {
    let json = r#"{"unknown":{}}"#;
    let result = serde_json::from_str::<ModuleType>(json);
    assert!(result.is_err());
  }
}
