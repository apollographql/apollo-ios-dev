/// Once set to true, stays true forever.
/// Mirrors Swift's @propertyWrapper IsEverTrue from Sources/Utilities/IsEverTrue.swift.
#[derive(Debug, Clone, Default)]
pub struct IsEverTrue {
    value: bool,
}

impl IsEverTrue {
    /// Creates a new IsEverTrue with initial value of false.
    pub fn new() -> Self {
        Self { value: false }
    }

    /// Returns the current value.
    pub fn get(&self) -> bool {
        self.value
    }

    /// Sets the value. Once set to true, it stays true forever.
    /// Setting to false after true has no effect.
    pub fn set(&mut self, new_value: bool) {
        if new_value {
            self.value = true;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_as_false() {
        let flag = IsEverTrue::new();
        assert!(!flag.get());
    }

    #[test]
    fn setting_true_makes_it_true() {
        let mut flag = IsEverTrue::new();
        flag.set(true);
        assert!(flag.get());
    }

    #[test]
    fn setting_false_after_true_keeps_it_true() {
        let mut flag = IsEverTrue::new();
        flag.set(true);
        flag.set(false);
        assert!(flag.get());
    }

    #[test]
    fn setting_false_when_false_keeps_it_false() {
        let mut flag = IsEverTrue::new();
        flag.set(false);
        assert!(!flag.get());
    }
}
