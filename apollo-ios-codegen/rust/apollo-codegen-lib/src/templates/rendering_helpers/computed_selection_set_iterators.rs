//! Selection set iterators for computed selection sets.
//!
//! Mirrors Swift's `ComputedSelectionSet+Iterators.swift` from
//! `Sources/ApolloCodegenLib/Templates/RenderingHelpers/ComputedSelectionSet+Iterators.swift`.

/// An iterator that yields items from a direct collection first, then from a merged collection,
/// with an optional filter applied.
///
/// Mirrors Swift's `IR.ComputedSelectionSet.SelectionsIterator` struct.
pub struct SelectionsIterator<T> {
  direct: Vec<T>,
  merged: Vec<T>,
  direct_index: usize,
  merged_index: usize,
  filter: Option<Box<dyn Fn(&T) -> bool>>,
}

impl<T> SelectionsIterator<T> {
  /// Creates a new `SelectionsIterator` with optional direct selections,
  /// merged selections, and an optional filter.
  pub fn new(
    direct: Option<Vec<T>>,
    merged: Vec<T>,
    filter: Option<Box<dyn Fn(&T) -> bool>>,
  ) -> Self {
    Self {
      direct: direct.unwrap_or_default(),
      merged,
      direct_index: 0,
      merged_index: 0,
      filter,
    }
  }

  /// Returns `true` if both direct and merged collections are empty.
  pub fn is_empty(&self) -> bool {
    self.direct.is_empty() && self.merged.is_empty()
  }
}

impl<T> Iterator for SelectionsIterator<T>
where
  T: Clone,
{
  type Item = T;

  fn next(&mut self) -> Option<Self::Item> {
    if let Some(ref filter) = self.filter {
      // With filter: skip items that don't match
      while self.direct_index < self.direct.len() {
        let item = &self.direct[self.direct_index];
        self.direct_index += 1;
        if filter(item) {
          return Some(item.clone());
        }
      }
      while self.merged_index < self.merged.len() {
        let item = &self.merged[self.merged_index];
        self.merged_index += 1;
        if filter(item) {
          return Some(item.clone());
        }
      }
      None
    } else {
      // Without filter: yield direct first, then merged
      if self.direct_index < self.direct.len() {
        let item = self.direct[self.direct_index].clone();
        self.direct_index += 1;
        return Some(item);
      }
      if self.merged_index < self.merged.len() {
        let item = self.merged[self.merged_index].clone();
        self.merged_index += 1;
        return Some(item);
      }
      None
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn test_empty_iterator() {
    let iter: SelectionsIterator<i32> = SelectionsIterator::new(None, vec![], None);
    assert!(iter.is_empty());
    assert_eq!(iter.collect::<Vec<_>>(), Vec::<i32>::new());
  }

  #[test]
  fn test_direct_only() {
    let iter = SelectionsIterator::new(Some(vec![1, 2, 3]), vec![], None);
    assert!(!iter.is_empty());
    assert_eq!(iter.collect::<Vec<_>>(), vec![1, 2, 3]);
  }

  #[test]
  fn test_merged_only() {
    let iter = SelectionsIterator::new(None, vec![4, 5, 6], None);
    assert!(!iter.is_empty());
    assert_eq!(iter.collect::<Vec<_>>(), vec![4, 5, 6]);
  }

  #[test]
  fn test_direct_then_merged() {
    let iter = SelectionsIterator::new(Some(vec![1, 2]), vec![3, 4], None);
    assert_eq!(iter.collect::<Vec<_>>(), vec![1, 2, 3, 4]);
  }

  #[test]
  fn test_with_filter() {
    let filter: Box<dyn Fn(&i32) -> bool> = Box::new(|x| *x % 2 == 0);
    let iter = SelectionsIterator::new(
      Some(vec![1, 2, 3, 4]),
      vec![5, 6, 7, 8],
      Some(filter),
    );
    assert_eq!(iter.collect::<Vec<_>>(), vec![2, 4, 6, 8]);
  }

  #[test]
  fn test_filter_empty_result() {
    let filter: Box<dyn Fn(&i32) -> bool> = Box::new(|x| *x > 100);
    let iter = SelectionsIterator::new(
      Some(vec![1, 2]),
      vec![3, 4],
      Some(filter),
    );
    assert_eq!(iter.collect::<Vec<_>>(), Vec::<i32>::new());
  }

  #[test]
  fn test_is_empty_with_none_direct() {
    let iter: SelectionsIterator<i32> = SelectionsIterator::new(None, vec![], None);
    assert!(iter.is_empty());
  }

  #[test]
  fn test_is_empty_with_empty_direct() {
    let iter: SelectionsIterator<i32> = SelectionsIterator::new(Some(vec![]), vec![], None);
    assert!(iter.is_empty());
  }

  #[test]
  fn test_is_not_empty_with_direct() {
    let iter = SelectionsIterator::new(Some(vec![1]), vec![], None);
    assert!(!iter.is_empty());
  }

  #[test]
  fn test_is_not_empty_with_merged() {
    let iter: SelectionsIterator<i32> = SelectionsIterator::new(None, vec![1], None);
    assert!(!iter.is_empty());
  }
}
