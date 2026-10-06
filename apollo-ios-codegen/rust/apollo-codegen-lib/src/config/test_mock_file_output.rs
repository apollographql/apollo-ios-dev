use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::access_modifier::AccessModifier;

/// Which schema object types a test mock output covers.
///
/// Fork extension (see [`TestMockScoping`]). `All` is Apollo's behaviour: one
/// `<Object>+Mock.swift` per object type referenced by any operation the
/// configuration can see.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum TestMockScope {
    /// Every object type referenced by the compiled operations (Apollo's behaviour).
    #[default]
    #[serde(rename = "all")]
    All,
    /// Only the object types referenced by the operations and fragments selected for
    /// generation (all of them outside Bazel mode; the `--bazel-generate-for` /
    /// `--bazel-framework-path` selection in Bazel mode), including the types reached
    /// through the interfaces and unions those definitions use.
    #[serde(rename = "referencedByOperations")]
    ReferencedByOperations,
}

/// Fork extension of `output.testMocks`: lets one configuration (or one Bazel
/// target) emit a subset of the schema's test mocks, so that a shared "base" mock
/// module and per-feature mock modules can be composed.
///
/// Accepted inside both the `absolute` and the `swiftPackage` objects:
///
/// ```json
/// "testMocks": {
///   "swiftPackage": {
///     "targetName": "AccountMocks",
///     "scope": "referencedByOperations",   // "all" (default) | "referencedByOperations"
///     "includeTypes": ["Dog"],              // always generated (must be referenced by some operation)
///     "excludeTypes": ["User", "Query"],    // never generated (unknown names are ignored)
///     "baseModule": "BaseMocks",            // adds `import BaseMocks` to every generated mock file
///     "includeTypealiases": false           // MockObject+Interfaces/Unions files; default: true
///                                           // without `baseModule`, false with it
///   }
/// }
/// ```
///
/// The effective set of mocked object types is `scope` ∪ `includeTypes` − `excludeTypes`.
/// The generated files are byte-identical to Apollo's for the same type; only the
/// selection, the optional `import <baseModule>` line and the typealias files change.
/// The `MockObject+Interfaces.swift` / `MockObject+Unions.swift` typealias files always
/// list every interface/union referenced by the whole configuration, so they must live
/// in exactly one module (the base).
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TestMockScoping {
    #[serde(default, skip_serializing_if = "is_default_scope")]
    pub scope: TestMockScope,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub include_types: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub exclude_types: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub base_module: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub include_typealiases: Option<bool>,
}

fn is_default_scope(scope: &TestMockScope) -> bool {
    *scope == TestMockScope::All
}

impl TestMockScoping {
    /// Whether the scoping is Apollo's default (every type, no base module).
    pub fn is_default(&self) -> bool {
        *self == TestMockScoping::default()
    }

    /// Whether the `MockObject+Interfaces` / `MockObject+Unions` typealias files are
    /// generated: `includeTypealiases` when set, otherwise only when no `baseModule`
    /// provides them.
    pub fn generates_typealiases(&self) -> bool {
        self.include_typealiases
            .unwrap_or(self.base_module.is_none())
    }
}

/// The local path structure for the generated test mock object files.
///
/// Mirrors Swift's `ApolloCodegenConfiguration.TestMockFileOutput` enum, extended
/// with the fork's [`TestMockScoping`] keys on the `absolute` and `swiftPackage` forms.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TestMockFileOutput {
    /// Test mocks will not be generated. This is the default value.
    None,
    /// Generated test mock files will be located in the specified `path`.
    /// `access_modifier` defaults to `Public`.
    Absolute {
        path: String,
        access_modifier: AccessModifier,
        scoping: TestMockScoping,
    },
    /// Generated test mock files will be included in a target defined in the generated
    /// `Package.swift` file. `target_name` defaults to `None`.
    SwiftPackage {
        target_name: Option<String>,
        scoping: TestMockScoping,
    },
}

impl TestMockFileOutput {
    /// The scoping of a configured output (`None` when test mocks are not generated).
    pub fn scoping(&self) -> Option<&TestMockScoping> {
        match self {
            TestMockFileOutput::None => Option::None,
            TestMockFileOutput::Absolute { scoping, .. }
            | TestMockFileOutput::SwiftPackage { scoping, .. } => Some(scoping),
        }
    }

    /// Mutable access to the scoping of a configured output.
    pub fn scoping_mut(&mut self) -> Option<&mut TestMockScoping> {
        match self {
            TestMockFileOutput::None => Option::None,
            TestMockFileOutput::Absolute { scoping, .. }
            | TestMockFileOutput::SwiftPackage { scoping, .. } => Some(scoping),
        }
    }
}

impl<'de> Deserialize<'de> for TestMockFileOutput {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct TestMockFileOutputVisitor;

        impl<'de> Visitor<'de> for TestMockFileOutputVisitor {
            type Value = TestMockFileOutput;

            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str(
                    "a TestMockFileOutput object with one key: none, absolute, or swiftPackage",
                )
            }

            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let key: String = map.next_key()?.ok_or_else(|| {
                    de::Error::custom("Invalid number of keys found, expected one.")
                })?;

                match key.as_str() {
                    "none" => {
                        let _: serde_json::Value = map.next_value()?;
                        Ok(TestMockFileOutput::None)
                    }
                    "absolute" => {
                        #[derive(Deserialize)]
                        struct Inner {
                            path: String,
                            #[serde(
                                rename = "accessModifier",
                                default = "crate::config::access_modifier::default_public"
                            )]
                            access_modifier: AccessModifier,
                            #[serde(flatten)]
                            scoping: TestMockScoping,
                        }
                        let inner: Inner = map.next_value()?;
                        Ok(TestMockFileOutput::Absolute {
                            path: inner.path,
                            access_modifier: inner.access_modifier,
                            scoping: inner.scoping,
                        })
                    }
                    "swiftPackage" => {
                        #[derive(Deserialize)]
                        struct Inner {
                            #[serde(rename = "targetName")]
                            target_name: Option<String>,
                            #[serde(flatten)]
                            scoping: TestMockScoping,
                        }
                        let inner: Inner = map.next_value()?;
                        Ok(TestMockFileOutput::SwiftPackage {
                            target_name: inner.target_name,
                            scoping: inner.scoping,
                        })
                    }
                    other => Err(de::Error::unknown_variant(
                        other,
                        &["none", "absolute", "swiftPackage"],
                    )),
                }
            }
        }

        deserializer.deserialize_map(TestMockFileOutputVisitor)
    }
}

impl Serialize for TestMockFileOutput {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            TestMockFileOutput::None => {
                let mut map = serializer.serialize_map(Some(1))?;
                map.serialize_entry("none", &serde_json::Map::new())?;
                map.end()
            }
            TestMockFileOutput::Absolute {
                path,
                access_modifier,
                scoping,
            } => {
                #[derive(Serialize)]
                #[serde(rename_all = "camelCase")]
                struct Inner<'a> {
                    path: &'a str,
                    access_modifier: &'a AccessModifier,
                    #[serde(flatten)]
                    scoping: &'a TestMockScoping,
                }
                let mut map = serializer.serialize_map(Some(1))?;
                map.serialize_entry(
                    "absolute",
                    &Inner {
                        path,
                        access_modifier,
                        scoping,
                    },
                )?;
                map.end()
            }
            TestMockFileOutput::SwiftPackage {
                target_name,
                scoping,
            } => {
                #[derive(Serialize)]
                #[serde(rename_all = "camelCase")]
                struct Inner<'a> {
                    target_name: &'a Option<String>,
                    #[serde(flatten)]
                    scoping: &'a TestMockScoping,
                }
                let mut map = serializer.serialize_map(Some(1))?;
                map.serialize_entry(
                    "swiftPackage",
                    &Inner {
                        target_name,
                        scoping,
                    },
                )?;
                map.end()
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_test_mock_none_roundtrip() {
        let json = r#"{"none":{}}"#;
        let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
        assert_eq!(parsed, TestMockFileOutput::None);
        let serialized = serde_json::to_string(&parsed).unwrap();
        assert_eq!(serialized, json);
    }

    #[test]
    fn test_test_mock_absolute_roundtrip() {
        let json = r#"{"absolute":{"path":"x","accessModifier":"internal"}}"#;
        let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
        assert_eq!(
            parsed,
            TestMockFileOutput::Absolute {
                path: "x".to_string(),
                access_modifier: AccessModifier::Internal,
                scoping: TestMockScoping::default(),
            }
        );
        let serialized = serde_json::to_string(&parsed).unwrap();
        assert_eq!(serialized, json);
    }

    #[test]
    fn test_test_mock_swift_package_roundtrip() {
        let json = r#"{"swiftPackage":{"targetName":"SchemaTestMocks"}}"#;
        let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
        assert_eq!(
            parsed,
            TestMockFileOutput::SwiftPackage {
                target_name: Some("SchemaTestMocks".to_string()),
                scoping: TestMockScoping::default(),
            }
        );
        let serialized = serde_json::to_string(&parsed).unwrap();
        assert_eq!(serialized, json);
    }

    #[test]
    fn test_test_mock_swift_package_no_target_name() {
        let json = r#"{"swiftPackage":{"targetName":null}}"#;
        let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
        assert_eq!(
            parsed,
            TestMockFileOutput::SwiftPackage {
                target_name: None,
                scoping: TestMockScoping::default(),
            }
        );
    }

    #[test]
    fn test_scoping_keys_roundtrip_on_swift_package() {
        let json = r#"{"swiftPackage":{"targetName":"AccountMocks","scope":"referencedByOperations","includeTypes":["Dog"],"excludeTypes":["User","Query"],"baseModule":"BaseMocks","includeTypealiases":false}}"#;
        let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
        let expected = TestMockScoping {
            scope: TestMockScope::ReferencedByOperations,
            include_types: vec!["Dog".to_string()],
            exclude_types: vec!["User".to_string(), "Query".to_string()],
            base_module: Some("BaseMocks".to_string()),
            include_typealiases: Some(false),
        };
        assert_eq!(parsed.scoping(), Some(&expected));
        assert!(!expected.generates_typealiases());
        assert_eq!(serde_json::to_string(&parsed).unwrap(), json);
    }

    #[test]
    fn test_scoping_keys_roundtrip_on_absolute() {
        let json = r#"{"absolute":{"path":"Mocks","accessModifier":"public","scope":"all","baseModule":"BaseMocks"}}"#;
        let parsed: TestMockFileOutput = serde_json::from_str(json).unwrap();
        let scoping = parsed.scoping().unwrap();
        assert_eq!(scoping.scope, TestMockScope::All);
        assert_eq!(scoping.base_module.as_deref(), Some("BaseMocks"));
        assert!(
            !scoping.generates_typealiases(),
            "a base module provides the typealiases"
        );
        // "scope":"all" is the default and is not re-emitted.
        assert_eq!(
            serde_json::to_string(&parsed).unwrap(),
            r#"{"absolute":{"path":"Mocks","accessModifier":"public","baseModule":"BaseMocks"}}"#
        );
    }

    #[test]
    fn test_scoping_defaults() {
        let parsed: TestMockFileOutput =
            serde_json::from_str(r#"{"swiftPackage":{"targetName":"M"}}"#).unwrap();
        let scoping = parsed.scoping().unwrap();
        assert!(scoping.is_default());
        assert!(scoping.generates_typealiases());
        assert!(serde_json::from_str::<TestMockFileOutput>(r#"{"none":{}}"#)
            .unwrap()
            .scoping()
            .is_none());
    }

    #[test]
    fn test_include_typealiases_true_with_base_module() {
        let parsed: TestMockFileOutput = serde_json::from_str(
            r#"{"swiftPackage":{"baseModule":"BaseMocks","includeTypealiases":true}}"#,
        )
        .unwrap();
        assert!(parsed.scoping().unwrap().generates_typealiases());
    }

    #[test]
    fn test_invalid_scope_is_rejected() {
        let err =
            serde_json::from_str::<TestMockFileOutput>(r#"{"swiftPackage":{"scope":"some"}}"#)
                .unwrap_err()
                .to_string();
        assert!(err.contains("unknown variant"), "{err}");
    }

    #[test]
    fn test_unknown_variant_still_rejected() {
        let err = serde_json::from_str::<TestMockFileOutput>(r#"{"scoped":{}}"#)
            .unwrap_err()
            .to_string();
        assert!(err.contains("unknown variant"), "{err}");
    }
}
