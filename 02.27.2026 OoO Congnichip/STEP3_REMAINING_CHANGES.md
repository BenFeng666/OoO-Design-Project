# Step 3 Remaining Changes

## Status: ✅ validate_reset_state() - DONE

## Still To Do:

### 1. Update `verify_full_architectural_state()` task

**Find this:**
```systemverilog
for (int i = 0; i < 32; i++) begin
    actual = dut.i_regfile.arch_regs[i];
```

**Replace with:**
```systemverilog
for (int i = 0; i < ARCH_REGS; i++) begin
    actual = get_arch_reg(i);
```

### 2. Update `check_rob_empty()` task

**Find this:**
```systemverilog
task check_rob_empty();
    $display("\nROB State Check:");
    if (dut.i_rob.entry_count == 0) begin
        $display("  ROB is empty (good)");
    end else begin
        $display("  WARNING: ROB has %0d entries remaining", dut.i_rob.entry_count);
    end
endtask
```

**Replace with:**
```systemverilog
task check_rob_empty();
    $display("\nROB State Check:");
    if (get_rob_entry_count() == 0) begin
        $display("  ROB is empty (good)");
    end else begin
        $display("  WARNING: ROB has %0d entries remaining", get_rob_entry_count());
    end
endtask
```

### 3. Update `check_rs_empty()` task

**Find this:**
```systemverilog
task check_rs_empty();
    static int valid_entries;
    
    valid_entries = 0;
    $display("\nReservation Station Check:");
    
    for (int i = 0; i < 8; i++) begin
        if (dut.i_rs.rs_entries[i].valid) begin
            valid_entries++;
        end
    end
```

**Replace with:**
```systemverilog
task check_rs_empty();
    static int valid_entries;
    
    valid_entries = count_rs_valid_entries();
    $display("\nReservation Station Check:");
```

### 4. Update `dump_microarch_state()` task

This one has MANY changes. Find all instances of:
- `safe_check_signal(dut.i_rob.entry_count)` → `get_rob_entry_count()`
- `safe_check_signal(dut.i_rob.head_ptr)` → `get_rob_head_ptr()`
- `safe_check_signal(dut.i_rob.tail_ptr)` → `get_rob_tail_ptr()`
- `safe_check_signal(dut.rob_full)` → `get_rob_full()`
- `safe_check_signal(dut.i_rob.rob_entries[i].valid)` → `get_rob_entry_valid(i)`
- Direct accesses to `dut.i_rob.rob_entries[i].*` → use `get_rob_entry_*()` functions
- `safe_check_signal(dut.rs_full)` → `get_rs_full()`
- `safe_check_signal(dut.i_rs.rs_entries[i].valid)` → `get_rs_entry_valid(i)`
- Pipeline signals: use `get_fetch_valid()`, `get_dispatch_valid()`, etc.

### 5. REMOVE old `safe_check_signal()` function

**Find and DELETE:**
```systemverilog
// Safe signal checking with X/Z detection
function automatic int safe_check_signal(input logic [31:0] sig);
    if ($isunknown(sig)) begin
        return -1;  // Indicate unknown
    end
    return sig;
endfunction
```

This function is no longer needed since we have type-specific functions now.

### 6. Update monitoring blocks

Find monitor blocks that use direct peeks like:
- `if (!reset && dut.dispatch_valid)` → `if (!reset && get_dispatch_valid())`
- `if (!reset && dut.cdb_valid)` → `if (!reset && get_cdb_valid())`
- `if (dut.rob_full)` → `if (get_rob_full())`
- `if (dut.rs_full)` → `if (get_rs_full())`

## Why We're Doing This

**Benefits of Abstraction Layer:**
1. ✅ **Single point of change** - if DUT hierarchy changes, update ONE function
2. ✅ **Bounds checking** - prevents array out-of-bounds crashes  
3. ✅ **Type safety** - proper types for all accessors
4. ✅ **Cleaner code** - `get_rob_entry_count()` vs `dut.i_rob.entry_count`
5. ✅ **Maintainable** - easier to read and understand

## After Step 3 Completes

We'll move on to:
- **Step 4**: Add comprehensive OoO invariant assertions (tag checks, RS/ROB consistency)
- **Step 5**: Add enforced pipeline drain verification
- **Step 6**: Add targeted wave dumping

Your testbench will then be fully production-ready! 🎉
