import IR
import OrderedCollections

extension IR.ComputedSelectionSet {

  typealias FieldIterator =
  SelectionsIterator<OrderedDictionary<String, IR.Field>.Values>

  typealias InlineFragmentIterator =
  SelectionsIterator<OrderedDictionary<ScopeCondition, IR.InlineFragmentSpread>.Values>

  typealias NamedFragmentIterator =
  SelectionsIterator<OrderedDictionary<String, IR.NamedFragmentSpread>.Values>

  func makeFieldIterator(
    filter: ((IR.Field) -> Bool)? = nil
  ) -> FieldIterator {
    SelectionsIterator(
      direct: direct?.fields.values,
      merged: merged.fields.values,
      filter: filter
    )
  }

  func makeInlineFragmentIterator(
    filter: ((IR.InlineFragmentSpread) -> Bool)? = nil
  ) -> InlineFragmentIterator {
    SelectionsIterator(
      direct: direct?.inlineFragments.values,
      merged: merged.inlineFragments.values,
      filter: filter
    )
  }

  func makeNamedFragmentIterator(
    filter: ((IR.NamedFragmentSpread) -> Bool)? = nil
  ) -> NamedFragmentIterator {
    SelectionsIterator(
      direct: direct?.namedFragments.values,
      merged: merged.namedFragments.values,
      filter: filter
    )
  }

  struct SelectionsIterator<SelectionCollection: Collection>: IteratorProtocol {
    typealias SelectionType = SelectionCollection.Element

    private let direct: SelectionCollection?
    private let merged: SelectionCollection
    private var directIterator: SelectionCollection.Iterator?
    private var mergedIterator: SelectionCollection.Iterator
    private let filter: ((SelectionType) -> Bool)?

    fileprivate init(
      direct: SelectionCollection?,
      merged: SelectionCollection,
      filter: ((SelectionType) -> Bool)?
    ) {
      self.direct = direct
      self.merged = merged
      self.directIterator = self.direct?.makeIterator()
      self.mergedIterator = self.merged.makeIterator()
      self.filter = filter
    }

    mutating func next() -> SelectionType? {
      guard let filter else {
        return directIterator?.next() ?? mergedIterator.next()
      }

      while let next = directIterator?.next() {
        if filter(next) { return next }
      }

      while let next = mergedIterator.next() {
        if filter(next) { return next }
      }

      return nil
    }

    var isEmpty: Bool {
      return (direct?.isEmpty ?? true) && merged.isEmpty
    }

  }

}
