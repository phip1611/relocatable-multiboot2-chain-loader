//! Helper module of the stack.

/// Canary value at the bottom of the stack to detect overflows.
pub const CANARY: u64 = 0x13371337_deadbeef;

/// Alignment of the stack. Must match the `repr` of the type!
pub const ALIGNMENT: usize = 16;

/// Minimum stack size.
pub const MIN_STACK_SIZE: usize = ALIGNMENT;

/// Default stack size.
pub const DEFAULT_STACK_SIZE: usize = 0x10000 /* 64 KiB */;

/// Error that indicates the stack canary was violated.
#[derive(Debug, Copy, Clone, Ord, PartialOrd, Eq, PartialEq, Hash)]
pub struct CanaryMissmatchError {
    expected: u64,
    actual: u64,
}

/// Properly aligned type holding backing memory for stack.
#[repr(C, align(16))]
pub struct Stack<const N: usize = DEFAULT_STACK_SIZE> {
    canary: u64,
    stack: [u8; N],
}

impl<const SIZE: usize> Stack<SIZE> {
    /// Constructs a new and properly aligned stack.
    pub const fn new() -> Self {
        assert!(SIZE >= MIN_STACK_SIZE);
        Self {
            canary: CANARY,
            stack: [0; SIZE],
        }
    }

    /// Returns the top of the usable stack.
    pub const fn top(&self) -> *mut u8 {
        unsafe { self.bottom().add(SIZE) }
    }

    /// Returns the top address of the stack that is properly aligned.
    /// On x86, the stack must be 16-byte aligned 8-byte under the current
    /// stack pointer. This way, the first stack argument after the return
    /// address is aligned.
    pub const fn adjusted_top(&self) -> *mut u8 {
        const FIRST_PARAMETER_OFFSET: usize = 8;
        unsafe { self.top().sub(ALIGNMENT).add(FIRST_PARAMETER_OFFSET) }
    }

    /// Returns the bottom of the usable stack.
    pub const fn bottom(&self) -> *mut u8 {
        self.stack.as_ptr().cast_mut()
    }

    /// Returns the current canary.
    pub const fn canary(&self) -> u64 {
        self.canary
    }

    /// Verifies if the canary is still correct.
    pub fn check_canary(&self) -> Result<(), CanaryMissmatchError> {
        // volatile: make sure that compiler never optimizes this away
        let actual = unsafe { core::ptr::read_volatile(core::ptr::addr_of!(self.canary)) };
        (actual == CANARY).then(|| ()).ok_or(CanaryMissmatchError {
            expected: CANARY,
            actual,
        })
    }
}

#[cfg(test)]
mod tests {
    use crate::mem::stack::{CanaryMissmatchError, Stack, ALIGNMENT, CANARY};
    use std::mem::{align_of, size_of};

    #[test]
    fn test_abi() {
        assert_eq!(align_of::<Stack>(), ALIGNMENT);
        assert_eq!(size_of::<Stack<8>>(), size_of::<u64>() + 8);
    }

    #[test]
    fn test_stack() {
        let mut stack: Stack = Stack::new();
        assert_eq!(Ok(()), stack.check_canary());
        stack.canary = 5;
        assert_eq!(
            Err(CanaryMissmatchError {
                expected: CANARY,
                actual: 5,
            }),
            stack.check_canary()
        );

        assert!(stack.bottom() < stack.top());
    }

    #[test]
    #[should_panic]
    fn test_small_stack_is_invalid() {
        let _stack = Stack::<{ALIGNMENT - 1}>::new();
    }
}
