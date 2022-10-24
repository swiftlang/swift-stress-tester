//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#ifndef InstructionCount_h
#define InstructionCount_h

#include <stdint.h>

/// Returns the number of instructions this process has executed since it was launched.
uint64_t get_current_instruction_count();

#endif /* InstructionCount_h */
