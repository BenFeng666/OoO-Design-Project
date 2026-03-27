
# Out of Order (OoO) Processor 🚀

A high-performance execution engine simulation. This project explores the transition from a traditional synchronous pipeline to a dynamic, out-of-order execution model.



---

## 📊 Current Status: Phase 1 (In-Order)
We are currently establishing the **In-Order Baseline**. This ensures that the fundamental architectural states—Fetch, Decode, Execute, Memory, and Writeback—are functioning correctly before we introduce the complexity of dynamic scheduling.

### Project Roadmap
- [x] **Phase 0:** Architecture Design & ISA Definition
- [> ] **Phase 1:** In-Order Pipeline (Testing passed)
- [> ] **Phase 2:** Out of Order Pipeline (Started)
- [ ] **Phase 3:** Testing and implementing on FPGA (Not started)


---

## 🛠 Progress Tracker

| Component | Status | Description |
| :--- | :--- | :--- |
| **Instruction Fetch** |🏗️ In Progress| Basic PC increment and memory interfacing. |
| **Decode Logic** | 🏗️ In Progress | Mapping opcodes to functional units. |
| **ALU / Execute** |🏗️ In Progress | Support for basic Integer Arithmetic. |
| **Hazard Unit** | 🏗️ In Progress | Implementing stalls for RAW dependencies. |
| **Memory/WB** | 🏗️ In Progress | Interfacing with Data Cache. |

---

## 🧩 Planned Features (Out-of-Order Phase)
Once the In-Order foundation is stable, the following OoO features will be implemented to increase **Instructions Per Cycle (IPC)**:



---

## 🚀 Getting Started

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/your-username/out-of-order.git](https://github.com/your-username/out-of-order.git)
