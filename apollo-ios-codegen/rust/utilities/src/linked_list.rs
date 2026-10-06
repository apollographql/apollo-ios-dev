use std::hash::{Hash, Hasher};
use std::ops::{Add, AddAssign, Index};

use serde::ser::{Serialize, Serializer};

/// A list type that is always non-empty, optimized for append and traversal.
/// Mirrors Swift's LinkedList from Sources/Utilities/LinkedList.swift.
///
/// Backed by Vec<T> -- provides O(1) amortized append, O(1) index, Clone semantics
/// (equivalent to Swift's copy-on-write).
#[derive(Debug, Clone)]
pub struct LinkedList<T> {
    items: Vec<T>,
}

impl<T> LinkedList<T> {
    /// Creates a single-element list with the given head value.
    pub fn new(head_value: T) -> Self {
        LinkedList {
            items: vec![head_value],
        }
    }

    /// Creates a list from a non-empty collection.
    /// Panics if the collection is empty.
    pub fn from_collection(items: impl IntoIterator<Item = T>) -> Self {
        let items: Vec<T> = items.into_iter().collect();
        assert!(
            !items.is_empty(),
            "Cannot initialize LinkedList with an empty collection. LinkedList must have at least one element."
        );
        LinkedList { items }
    }

    /// The head (first) element in the list.
    pub fn head(&self) -> &T {
        &self.items[0]
    }

    /// The last element in the list.
    pub fn last(&self) -> &T {
        self.items.last().expect("LinkedList is never empty")
    }

    /// Appends a value to the end of the list.
    pub fn append(&mut self, value: T) {
        self.items.push(value);
    }

    /// Appends all elements from an iterator to the end of the list.
    pub fn append_sequence(&mut self, iter: impl IntoIterator<Item = T>) {
        self.items.extend(iter);
    }

    /// Returns the element at the given position.
    pub fn node_at(&self, position: usize) -> &T {
        &self.items[position]
    }

    /// The number of elements in the list.
    pub fn count(&self) -> usize {
        self.items.len()
    }

    /// Always returns false -- LinkedList requires at least one element.
    pub fn is_empty(&self) -> bool {
        false
    }

    /// Replaces the last element by applying the given function.
    pub fn mutate_last(&mut self, f: impl FnOnce(T) -> T)
    where
        T: Default,
    {
        let last_idx = self.items.len() - 1;
        let old = std::mem::take(&mut self.items[last_idx]);
        self.items[last_idx] = f(old);
    }

    /// Returns an iterator over references to the elements.
    pub fn iter(&self) -> std::slice::Iter<'_, T> {
        self.items.iter()
    }
}

impl<T: Clone> LinkedList<T> {
    /// Returns a new list with the value appended, without mutating the original.
    pub fn appending(&self, value: T) -> Self {
        let mut new_items = self.items.clone();
        new_items.push(value);
        LinkedList { items: new_items }
    }

    /// Returns a new list with all elements from the iterator appended.
    pub fn appending_sequence(&self, iter: impl IntoIterator<Item = T>) -> Self {
        let mut new_items = self.items.clone();
        new_items.extend(iter);
        LinkedList { items: new_items }
    }

    /// Returns a new list with the last element replaced by applying the given function.
    pub fn mutating_last(&self, f: impl FnOnce(T) -> T) -> Self {
        let mut new_items = self.items.clone();
        let last_idx = new_items.len() - 1;
        let old = new_items.remove(last_idx);
        new_items.push(f(old));
        LinkedList { items: new_items }
    }
}

// -- Index trait --

impl<T> Index<usize> for LinkedList<T> {
    type Output = T;

    fn index(&self, index: usize) -> &Self::Output {
        &self.items[index]
    }
}

// -- IntoIterator for &LinkedList --

impl<'a, T> IntoIterator for &'a LinkedList<T> {
    type Item = &'a T;
    type IntoIter = std::slice::Iter<'a, T>;

    fn into_iter(self) -> Self::IntoIter {
        self.items.iter()
    }
}

// -- IntoIterator for LinkedList (consuming) --

impl<T> IntoIterator for LinkedList<T> {
    type Item = T;
    type IntoIter = std::vec::IntoIter<T>;

    fn into_iter(self) -> Self::IntoIter {
        self.items.into_iter()
    }
}

// -- PartialEq --

impl<T: PartialEq> PartialEq for LinkedList<T> {
    fn eq(&self, other: &Self) -> bool {
        self.items == other.items
    }
}

// -- Eq --

impl<T: Eq> Eq for LinkedList<T> {}

// -- Hash --

impl<T: Hash> Hash for LinkedList<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.items.hash(state);
    }
}

// -- Serialize --

impl<T: Serialize> Serialize for LinkedList<T> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.items.serialize(serializer)
    }
}

// -- Add operator (LinkedList + Vec) --

impl<T: Clone> Add<Vec<T>> for LinkedList<T> {
    type Output = LinkedList<T>;

    fn add(self, rhs: Vec<T>) -> Self::Output {
        self.appending_sequence(rhs)
    }
}

// -- AddAssign operator (LinkedList += Vec) --

impl<T> AddAssign<Vec<T>> for LinkedList<T> {
    fn add_assign(&mut self, rhs: Vec<T>) {
        self.append_sequence(rhs);
    }
}

// -- NodeRef for node-by-node traversal --

impl<T> LinkedList<T> {
    /// Returns a NodeRef to the head (first) node.
    /// Matches Swift's `list.head` which returns a Node.
    pub fn head_node(&self) -> NodeRef<'_, T> {
        NodeRef { list: self, index: 0 }
    }

    /// Returns a NodeRef to the last node.
    /// Matches Swift's `list.last` which returns a Node.
    pub fn last_node(&self) -> NodeRef<'_, T> {
        NodeRef {
            list: self,
            index: self.items.len() - 1,
        }
    }
}

/// A lightweight reference to a node in a LinkedList, providing
/// Swift-style .value/.next/.previous navigation.
/// Maps 1:1 to Swift's LinkedList<T>.Node.
#[derive(Debug)]
pub struct NodeRef<'a, T> {
    list: &'a LinkedList<T>,
    index: usize,
}

// Manual Clone/Copy impls without requiring T: Clone/Copy,
// since NodeRef only holds a shared reference and a usize.
impl<'a, T> Clone for NodeRef<'a, T> {
    fn clone(&self) -> Self {
        *self
    }
}

impl<'a, T> Copy for NodeRef<'a, T> {}

impl<'a, T> NodeRef<'a, T> {
    /// The value at this node position.
    pub fn value(&self) -> &'a T {
        &self.list[self.index]
    }

    /// The next node, or None if this is the last.
    pub fn next(&self) -> Option<NodeRef<'a, T>> {
        if self.index + 1 < self.list.count() {
            Some(NodeRef {
                list: self.list,
                index: self.index + 1,
            })
        } else {
            None
        }
    }

    /// The previous node, or None if this is the first (head).
    pub fn previous(&self) -> Option<NodeRef<'a, T>> {
        if self.index > 0 {
            Some(NodeRef {
                list: self.list,
                index: self.index - 1,
            })
        } else {
            None
        }
    }

    /// The index of this node in the list.
    pub fn index(&self) -> usize {
        self.index
    }
}

impl<T: PartialEq> PartialEq for NodeRef<'_, T> {
    fn eq(&self, other: &Self) -> bool {
        std::ptr::eq(self.list, other.list) && self.index == other.index
    }
}

// -- CustomDebugStringConvertible equivalent --

impl<T: std::fmt::Display> std::fmt::Display for LinkedList<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "[")?;
        for (i, item) in self.items.iter().enumerate() {
            if i > 0 {
                write!(f, " -> ")?;
            }
            write!(f, "{}", item)?;
        }
        write!(f, "]")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::hash_map::DefaultHasher;

    fn hash_of<T: Hash>(value: &T) -> u64 {
        let mut hasher = DefaultHasher::new();
        value.hash(&mut hasher);
        hasher.finish()
    }

    // -- LinkedList::new --

    #[test]
    fn new_creates_single_element_list() {
        let list = LinkedList::new(42);
        assert_eq!(list.count(), 1);
        assert_eq!(*list.head(), 42);
        assert_eq!(*list.last(), 42);
    }

    // -- append --

    #[test]
    fn append_adds_to_end() {
        let mut list = LinkedList::new(1);
        list.append(2);
        assert_eq!(list.count(), 2);
        assert_eq!(*list.last(), 2);
    }

    #[test]
    fn append_increments_count() {
        let mut list = LinkedList::new(1);
        list.append(2);
        list.append(3);
        assert_eq!(list.count(), 3);
    }

    // -- node_at / Index --

    #[test]
    fn node_at_zero_returns_head() {
        let list = LinkedList::new(10);
        assert_eq!(*list.node_at(0), 10);
    }

    #[test]
    fn node_at_last_returns_last() {
        let mut list = LinkedList::new(1);
        list.append(2);
        list.append(3);
        assert_eq!(*list.node_at(list.count() - 1), 3);
    }

    #[test]
    fn index_operator_works() {
        let mut list = LinkedList::new(10);
        list.append(20);
        list.append(30);
        assert_eq!(list[0], 10);
        assert_eq!(list[1], 20);
        assert_eq!(list[2], 30);
    }

    // -- appending (non-mutating) --

    #[test]
    fn appending_returns_new_list_without_mutating_original() {
        let list = LinkedList::new(1);
        let new_list = list.appending(2);
        assert_eq!(list.count(), 1);
        assert_eq!(new_list.count(), 2);
        assert_eq!(new_list[1], 2);
    }

    // -- mutate_last --

    #[test]
    fn mutate_last_replaces_last_element() {
        let mut list = LinkedList::new(1);
        list.append(2);
        list.mutate_last(|v| v * 10);
        assert_eq!(*list.last(), 20);
    }

    #[test]
    fn mutate_last_on_single_element() {
        let mut list = LinkedList::new(5);
        list.mutate_last(|v| v + 1);
        assert_eq!(*list.head(), 6);
    }

    // -- mutating_last (non-mutating) --

    #[test]
    fn mutating_last_returns_new_list() {
        let list = LinkedList::new(1);
        let new_list = list.mutating_last(|v| v * 10);
        assert_eq!(*list.head(), 1);
        assert_eq!(*new_list.head(), 10);
    }

    // -- from_collection --

    #[test]
    fn from_collection_creates_correct_list() {
        let list = LinkedList::from_collection(vec![1, 2, 3]);
        assert_eq!(list.count(), 3);
        assert_eq!(list[0], 1);
        assert_eq!(list[1], 2);
        assert_eq!(list[2], 3);
    }

    #[test]
    #[should_panic(expected = "Cannot initialize LinkedList with an empty collection")]
    fn from_collection_panics_on_empty() {
        let _list = LinkedList::from_collection(Vec::<i32>::new());
    }

    // -- is_empty --

    #[test]
    fn is_empty_always_returns_false() {
        let list = LinkedList::new(1);
        assert!(!list.is_empty());
    }

    // -- Iterator --

    #[test]
    fn iterator_yields_all_elements_in_order() {
        let mut list = LinkedList::new(1);
        list.append(2);
        list.append(3);
        let collected: Vec<&i32> = list.iter().collect();
        assert_eq!(collected, vec![&1, &2, &3]);
    }

    // -- PartialEq / Eq --

    #[test]
    fn equal_lists_are_equal() {
        let mut list1 = LinkedList::new(1);
        list1.append(2);
        let mut list2 = LinkedList::new(1);
        list2.append(2);
        assert_eq!(list1, list2);
    }

    #[test]
    fn different_lists_are_not_equal() {
        let list1 = LinkedList::new(1);
        let list2 = LinkedList::new(2);
        assert_ne!(list1, list2);
    }

    // -- Hash --

    #[test]
    fn equal_lists_produce_same_hash() {
        let mut list1 = LinkedList::new(1);
        list1.append(2);
        let mut list2 = LinkedList::new(1);
        list2.append(2);
        assert_eq!(hash_of(&list1), hash_of(&list2));
    }

    // -- Add operator (list + sequence) --

    #[test]
    fn add_operator_appends_vec() {
        let list = LinkedList::new(1);
        let new_list = list + vec![2, 3];
        assert_eq!(new_list.count(), 3);
        assert_eq!(new_list[0], 1);
        assert_eq!(new_list[1], 2);
        assert_eq!(new_list[2], 3);
    }

    // -- AddAssign operator --

    #[test]
    fn add_assign_appends_vec() {
        let mut list = LinkedList::new(1);
        list += vec![2, 3];
        assert_eq!(list.count(), 3);
        assert_eq!(list[2], 3);
    }

    // -- Bidirectional traversal (confirmed via index access from both ends) --

    #[test]
    fn bidirectional_traversal_via_index() {
        let list = LinkedList::from_collection(vec![10, 20, 30, 40, 50]);
        // Forward
        assert_eq!(list[0], 10);
        assert_eq!(list[1], 20);
        assert_eq!(list[2], 30);
        // Backward (via index from end)
        assert_eq!(list[4], 50);
        assert_eq!(list[3], 40);
        assert_eq!(list[2], 30);
    }

    // -- append_sequence --

    #[test]
    fn append_sequence_adds_multiple() {
        let mut list = LinkedList::new(1);
        list.append_sequence(vec![2, 3, 4]);
        assert_eq!(list.count(), 4);
        assert_eq!(list[3], 4);
    }

    // -- appending_sequence --

    #[test]
    fn appending_sequence_returns_new_list() {
        let list = LinkedList::new(1);
        let new_list = list.appending_sequence(vec![2, 3]);
        assert_eq!(list.count(), 1);
        assert_eq!(new_list.count(), 3);
    }

    // -- NodeRef tests --

    #[test]
    fn head_node_value_returns_first_element() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        assert_eq!(*list.head_node().value(), 10);
    }

    #[test]
    fn last_node_value_returns_last_element() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        assert_eq!(*list.last_node().value(), 30);
    }

    #[test]
    fn head_node_next_returns_second_element() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        let second = list.head_node().next().unwrap();
        assert_eq!(*second.value(), 20);
    }

    #[test]
    fn last_node_previous_returns_second_to_last() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        let second_to_last = list.last_node().previous().unwrap();
        assert_eq!(*second_to_last.value(), 20);
    }

    #[test]
    fn head_node_previous_is_none() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        assert!(list.head_node().previous().is_none());
    }

    #[test]
    fn last_node_next_is_none() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        assert!(list.last_node().next().is_none());
    }

    #[test]
    fn forward_traversal_visits_all_elements() {
        let list = LinkedList::from_collection(vec![1, 2, 3, 4, 5]);
        let mut values = Vec::new();
        let mut current = Some(list.head_node());
        while let Some(node) = current {
            values.push(*node.value());
            current = node.next();
        }
        assert_eq!(values, vec![1, 2, 3, 4, 5]);
    }

    #[test]
    fn backward_traversal_visits_all_elements_in_reverse() {
        let list = LinkedList::from_collection(vec![1, 2, 3, 4, 5]);
        let mut values = Vec::new();
        let mut current = Some(list.last_node());
        while let Some(node) = current {
            values.push(*node.value());
            current = node.previous();
        }
        assert_eq!(values, vec![5, 4, 3, 2, 1]);
    }

    #[test]
    fn single_element_head_node_next_is_none() {
        let list = LinkedList::new(42);
        assert!(list.head_node().next().is_none());
    }

    #[test]
    fn single_element_head_node_previous_is_none() {
        let list = LinkedList::new(42);
        assert!(list.head_node().previous().is_none());
    }

    #[test]
    fn single_element_head_and_last_are_same() {
        let list = LinkedList::new(42);
        assert_eq!(list.head_node(), list.last_node());
    }

    #[test]
    fn node_ref_index_is_correct() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        assert_eq!(list.head_node().index(), 0);
        assert_eq!(list.head_node().next().unwrap().index(), 1);
        assert_eq!(list.last_node().index(), 2);
    }

    #[test]
    fn node_ref_equality_same_list_same_index() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        let a = list.head_node();
        let b = list.head_node();
        assert_eq!(a, b);
    }

    #[test]
    fn node_ref_equality_different_index() {
        let list = LinkedList::from_collection(vec![10, 20, 30]);
        let a = list.head_node();
        let b = list.last_node();
        assert_ne!(a, b);
    }
}
