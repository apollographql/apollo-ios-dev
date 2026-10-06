use rayon::prelude::*;

/// Parallel map that filters None results and preserves input order.
/// Mirrors Swift's Collection.concurrentCompactMap from
/// Sources/Utilities/Collection+ConcurrentCompactMap.swift.
///
/// Calls `transform` on each element in parallel using rayon, then
/// collects non-None results in the original input order.
pub fn concurrent_compact_map<T, U, F>(items: &[T], transform: F) -> Vec<U>
where
    T: Sync,
    U: Send,
    F: Fn(&T) -> Option<U> + Sync,
{
    items
        .par_iter()
        .map(&transform)
        .collect::<Vec<_>>()
        .into_iter()
        .flatten()
        .collect()
}

/// Error-handling variant of concurrent_compact_map.
/// Maps items in parallel, collecting results and propagating the first error.
pub fn concurrent_compact_map_result<T, U, E, F>(items: &[T], transform: F) -> Result<Vec<U>, E>
where
    T: Sync,
    U: Send,
    E: Send,
    F: Fn(&T) -> Result<Option<U>, E> + Sync,
{
    let results: Result<Vec<Option<U>>, E> = items
        .par_iter()
        .map(&transform)
        .collect();

    results.map(|opts| opts.into_iter().flatten().collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_all_elements() {
        let input = vec![1, 2, 3];
        let result = concurrent_compact_map(&input, |x| Some(x * 2));
        assert_eq!(result, vec![2, 4, 6]);
    }

    #[test]
    fn filters_none_results() {
        let input = vec![1, 2, 3];
        let result = concurrent_compact_map(&input, |x| {
            if *x > 1 { Some(*x) } else { None }
        });
        assert_eq!(result, vec![2, 3]);
    }

    #[test]
    fn empty_input_returns_empty() {
        let input: Vec<i32> = vec![];
        let result = concurrent_compact_map(&input, |x| Some(x * 2));
        assert!(result.is_empty());
    }

    #[test]
    fn preserves_order() {
        let input: Vec<i32> = (0..100).collect();
        let result = concurrent_compact_map(&input, |x| Some(*x));
        let expected: Vec<i32> = (0..100).collect();
        assert_eq!(result, expected);
    }

    #[test]
    fn result_variant_maps_all_elements() {
        let input = vec![1, 2, 3];
        let result: Result<Vec<i32>, String> =
            concurrent_compact_map_result(&input, |x| Ok(Some(x * 2)));
        assert_eq!(result.unwrap(), vec![2, 4, 6]);
    }

    #[test]
    fn result_variant_propagates_error() {
        let input = vec![1, 2, 3];
        let result: Result<Vec<i32>, String> =
            concurrent_compact_map_result(&input, |x| {
                if *x == 2 {
                    Err("error at 2".to_string())
                } else {
                    Ok(Some(*x))
                }
            });
        assert!(result.is_err());
    }
}
