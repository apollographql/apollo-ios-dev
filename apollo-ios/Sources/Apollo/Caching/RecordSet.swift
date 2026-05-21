/// A set of cache records.
public struct RecordSet: Sendable, Hashable {
  public private(set) var storage: [CacheKey: Record] = [:]

  public init<S: Sequence>(records: S) where S.Iterator.Element == Record {
    insert(contentsOf: records)
  }

  public mutating func insert(_ record: Record) {
    storage[record.key] = record
  }

  public mutating func removeRecord(for key: CacheKey) {
    storage.removeValue(forKey: key)
  }

  public mutating func removeRecords(matching pattern: CacheKey) {
    for (key, _) in storage {
      if key.range(of: pattern, options: .caseInsensitive) != nil {
        storage.removeValue(forKey: key)
      }
    }
  }

  public mutating func clear() {
    storage.removeAll()
  }

  public mutating func insert<S: Sequence>(contentsOf records: S) where S.Iterator.Element == Record {
    for record in records {
      insert(record)
    }
  }

  public subscript(key: CacheKey) -> Record? {
    return storage[key]
  }

  public var isEmpty: Bool {
    return storage.isEmpty
  }

  public var keys: Set<CacheKey> {
    return Set(storage.keys)
  }

  @discardableResult public mutating func merge(records: RecordSet) -> Set<CacheKey> {
    var changedKeys: Set<CacheKey> = Set()

    for (_, record) in records.storage {
      changedKeys.formUnion(merge(record: record))
    }

    return changedKeys
  }

  @discardableResult public mutating func merge(record: Record) -> Set<CacheKey> {
    if let oldRecord = storage[record.key] {
      var changedKeys: Set<CacheKey> = Set()
      var updatedRecord = oldRecord

      // Always take the new `CachedField` so the stored timestamp advances
      // to the latest write. Only notify watchers (via `changedKeys`) when
      // the observable value actually differs from what was stored.
      for (key, newField) in record.fields {
        updatedRecord.fields[key] = newField
        if let oldField = oldRecord.fields[key],
           AnyHashable(oldField.value) == AnyHashable(newField.value) {
          continue
        }
        changedKeys.insert([record.key, key].joined(separator: "."))
      }

      storage[record.key] = updatedRecord
      return changedKeys
    } else {
      storage[record.key] = record
      return Set(record.fields.keys.map { [record.key, $0].joined(separator: ".") })
    }
  }
}

extension RecordSet: ExpressibleByDictionaryLiteral {
  /// Convenience for building a `RecordSet` from a literal. Values are
  /// raw field maps (`[CacheKey: any Hashable & Sendable]`) — each is
  /// wrapped into `CachedField`s with `writtenAt = 0` via `Record`'s
  /// convenience initializer.
  public init(dictionaryLiteral elements: (CacheKey, [CacheKey: Record.Value])...) {
    self.init(records: elements.map { Record(key: $0.0, $0.1) })
  }
}

extension RecordSet: CustomStringConvertible {
  public var description: String {
    return String(describing: Array(storage.values))
  }
}

extension RecordSet: CustomDebugStringConvertible {
  public var debugDescription: String {
    return description
  }
}

extension RecordSet: CustomPlaygroundDisplayConvertible {
  public var playgroundDescription: Any {
    return description
  }
}
