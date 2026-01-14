# AI Code Mentor - Product Specification

## 🎯 Sản phẩm là gì

**AI Code Mentor** - Một Neovim plugin hoạt động như một "mentor cá nhân" ngay trong editor, giúp developer học và hiểu code thay vì chỉ sinh code tự động.

### Concept Core
Thay vì AI **viết code thay bạn** (như Copilot), AI **dạy bạn** thông qua:
- Trả lời câu hỏi qua comment: `// Q: TCP socket options gồm những gì?`
- Giải thích concepts, không chỉ cho solution
- Review code và chỉ ra best practices
- Gợi ý tiếp theo để học sâu hơn

### Khác biệt chính với Copilot
| Copilot | AI Code Mentor |
|---------|----------------|
| Sinh code tự động | Giải thích để bạn tự viết |
| Tab-autocomplete | Comment-based Q&A |
| Optimize cho tốc độ | Optimize cho learning |
| Bạn ít code hơn | Bạn code 100% |
| Hiểu nông | Hiểu sâu |

---

## 💡 Nhu cầu của tôi (Nguyễn Mỹ Thống)

### 1. Kiểm soát hoàn toàn code
**Vấn đề**: Copilot generate code → tôi chỉ accept → não không xử lý sâu → không học được gì.

**Giải pháp**: AI chỉ trả lời câu hỏi → tôi tự viết từng dòng → muscle memory được build → học thực sự.

### 2. Học tech stack mới siêu nhanh
**Vấn đề hiện tại**:
- Học Rust/Go/new framework → phải:
  - Mở browser tìm docs
  - Đọc 5-10 bài khác nhau
  - Context switch → mất focus
  - Quay lại code và cố nhớ

**Với AI Mentor**:
```go
// Q: Trong Go, tôi nên dùng channel hay mutex cho concurrent counter?
// → Nhận câu trả lời ngay, không rời editor
// → Có examples cụ thể với trade-offs
// → Tự implement dựa trên hiểu biết
```

**Kết quả**: Học nhanh gấp 3-5 lần vì:
- Zero context switching
- Answers contextual cho đúng code đang viết
- Tự tay implement → nhớ lâu hơn

### 3. Real-time code review
**Vấn đề**: Solo developer, không có senior review code.

**Giải pháp**:
```python
# R: Review đoạn này về security và performance
def process_user_input(data):
    result = eval(data)  # Dangerous!
    return result

# → AI sẽ point out: eval() là security risk, suggest alternatives
```

### 4. Tích lũy knowledge base cá nhân
**Vấn đề**: Học được kiến thức nhưng quên sau vài tuần.

**Giải pháp**: Mọi Q&A được lưu lại, search được:
- "Lần trước tôi đã hỏi gì về goroutine?"
- "Những pattern nào tôi đã học về error handling?"
- Export thành markdown để review định kỳ

### 5. Các mode học tập khác nhau

| Mode | Prefix | Use Case |
|------|--------|----------|
| Question | `// Q:` | Hỏi trực tiếp, nhận answer ngay |
| Socratic | `// S:` | AI đặt câu hỏi ngược để guide thinking |
| Review | `// R:` | Code review chi tiết |
| Debug | `// D:` | Debug assistance, teach debugging skills |
| Explain | `// E:` | Deep dive vào concept |

**Example workflow**:
```javascript
// S: Tại sao async/await tốt hơn callback hell?
// → AI không answer trực tiếp, mà hỏi:
//    "Bạn thấy vấn đề gì khi nest 5 callback?"
//    "Promise giải quyết problem nào?"
//    → Guide bạn tự discover answer
```

---

## 🎓 Context: Tôi là ai

- **Sinh viên năm 3** - Khoa học Máy tính, UIT
- **Đam mê**: Web Apps, AI, Game Dev
- **Tech stack**: Go, Python, TypeScript, Rust (đang học)
- **Kinh nghiệm**: 
  - MultiAgent LLM for Pentesting (UIT InSecLab)
  - VisualHive - Data Ingestion Platform (Visual Hive)
  - 10+ projects với diverse stack
- **Setup**: Neovim + LazyVim, Arch + Hyprland
- **Role**: Head Developer tại GDSC UIT

### Pain Points cụ thể
1. Học Rust: ownership/borrowing khó → cần explain real-time trong code
2. Optimize performance: không biết bottleneck ở đâu → cần guide debugging
3. Best practices: thiếu senior review → cần AI mentor
4. Knowledge retention: học nhiều nhưng quên nhanh → cần knowledge system
5. Teaching others: là Head Dev cần giúp members → muốn share knowledge base

---

## ✨ Core Features (MVP)

### 1. Comment-based Interaction
```lua
-- Trong bất kỳ file code nào
// Q: Hàm này có memory leak không?

-- Nhấn <leader>ma (mentor ask)
-- → Floating window hiện:
--   💡 Answer:
--   Có thể có leak nếu không free buffer.
--   Trong Go, nên dùng defer để cleanup...
```

### 2. Context-Aware Answers
AI nhận được:
- Code xung quanh (50 lines)
- Language/framework đang dùng
- Current function context (via Tree-sitter)
- (Advanced) Related code trong codebase

### 3. Multiple Learning Modes
- **Q**: Direct answer
- **S**: Socratic questioning
- **R**: Code review
- **D**: Debug assistant
- **E**: Deep explanation

### 4. Incremental Hints
Hỏi câu khó → AI cho hint level 1 (subtle)
Hỏi lại → hint level 2 (clearer)
Hỏi lần 3 → hint level 3 (partial solution)
Lần 4 → full solution

### 5. Knowledge Tracking
- Tự động save mọi Q&A
- Search history: "concurrency Go"
- Export to markdown
- Track learning progress

---

## 🚀 Use Cases Cụ Thể

### Use Case 1: Học Rust mới
```rust
// Q: Tại sao closure này không compile?
let mut count = 0;
let increment = || count += 1;
increment();
println!("{}", count);

// → AI explain về mutable borrow rules
// → Tôi tự fix dựa trên understanding
// → Học được ownership concept
```

### Use Case 2: Debug Production Issue
```python
# D: Function này đôi khi return None, tại sao?
def get_user(user_id):
    user = cache.get(user_id)
    if user:
        return user
    return db.query(user_id)

# → AI guide:
#    "Cache.get() có thể return None hoặc False.
#     Bạn nên check explicitly: if user is not None"
# → Tôi fix và hiểu được subtle bug
```

### Use Case 3: Review Before PR
```typescript
// R: Review code này trước khi PR
async function processOrders(orders: Order[]) {
  for (const order of orders) {
    await processOne(order);
  }
}

// → AI point out:
//   ⚠️ Performance: Sequential processing slow
//   💡 Suggestion: Use Promise.all() for parallel
//   ✅ Good: Type safety với TypeScript
```

### Use Case 4: Learn New Library
```go
// E: Explain goroutine vs thread
// → AI explain deeply:
//   1. What: Lightweight concurrent execution
//   2. Why: OS threads expensive, goroutines cheap
//   3. How: M:N scheduling model
//   4. When: IO-bound tasks, concurrent processing
//   5. Example: [code example]
```

---

## 📊 Success Metrics

### Cá nhân
- [ ] Học Rust nhanh gấp 3 lần (từ 3 tháng → 1 tháng)
- [ ] Knowledge base 100+ entries sau 3 tháng
- [ ] Zero context switch ra browser khi code
- [ ] Hiểu sâu 100% code tự viết

### GDSC UIT Community
- [ ] 10+ members active sử dụng
- [ ] Learning speed improve đo được
- [ ] Share knowledge base trong team
- [ ] Onboard new members nhanh hơn

### Technical
- [ ] Response time <5s
- [ ] 90%+ answer accuracy
- [ ] Codebase-aware (với RAG)
- [ ] Zero performance impact trên editor

---

## 🎯 MVP Scope (2 tuần đầu)

### Must Have
1. Parse comment `// Q:` 
2. Gọi Claude API với code context
3. Render answer trong floating window
4. Keybinding smooth: `<leader>ma`

### Nice to Have (v2)
- Multiple modes (S/R/D/E)
- Incremental hints
- Knowledge tracking
- RAG cho project-wide context

### Out of Scope (MVP)
- Code generation
- Autocomplete
- Multi-file refactoring
- Team collaboration features

---

## 💭 Philosophy

> "Teach a person to fish, don't fish for them."

AI Code Mentor không làm việc thay bạn, nó dạy bạn cách làm tốt hơn.

### Design Principles
1. **Learning over Speed**: Optimize cho hiểu sâu, không phải code nhanh
2. **Guide, Don't Give**: Hướng dẫn tư duy, không cho solution trực tiếp
3. **Context is King**: Answer phải relevant với code đang viết
4. **Build Knowledge**: Tích lũy, không throwaway
5. **Stay in Flow**: Zero context switch, không gián đoạn coding

---

## 🎬 Demo Scenario

**Scene**: Đang code HTTP server bằng Go, gặp vấn đề timeout

```go
func main() {
    http.HandleFunc("/", handler)
    http.ListenAndServe(":8080", nil)
}

// Q: Server này thiếu gì về production-readiness?

[Nhấn <leader>ma]

┌─────────────────────────────────────┐
│   🧑‍🏫 Code Mentor                     │
├─────────────────────────────────────┤
│ ❓ Question:                         │
│ Server này thiếu gì về              │
│ production-readiness?               │
│                                     │
│ 💡 Answer:                          │
│ Server này thiếu several critical   │
│ configurations:                     │
│                                     │
│ 1. **Timeouts**: Không set         │
│    ReadTimeout, WriteTimeout →     │
│    vulnerable to slowloris attack  │
│                                     │
│ 2. **Graceful Shutdown**: Không    │
│    handle SIGTERM → connections    │
│    dropped khi deploy              │
│                                     │
│ 3. **Error Handling**: ListenAnd   │
│    Serve error không check         │
│                                     │
│ Bạn nên dùng http.Server struct    │
│ với explicit config. Tham khảo:    │
│ https://blog.cloudflare.com/...    │
│                                     │
│ [q: close | y: copy answer]        │
└─────────────────────────────────────┘
```

**Kết quả**: 
- Học được 3 concepts quan trọng
- Không phải Google → doc → back
- Tự implement dựa trên understanding
- Save vào knowledge base để reference sau

---

## 🔮 Vision dài hạn

### V1.0 (MVP)
- Comment-based Q&A
- Single file context
- Basic knowledge tracking

### V2.0 (3 tháng)
- 5 interaction modes
- Incremental hints
- Project-wide context (RAG)
- Export knowledge graph

### V3.0 (6 tháng)
- Team knowledge sharing
- AI-suggested learning paths
- Integration với Obsidian/Notion
- Metrics on learning progress

### V4.0 (1 năm)
- Multi-language support (Vietnamese)
- Custom mentor personalities
- Community marketplace (share knowledge bases)
- Potential: Standalone product/startup
