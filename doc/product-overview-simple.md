# AI Code Mentor - Nhu Cầu & Product Overview

## 📋 NHU CẦU CỦA BẠN

| Vấn đề hiện tại | Mong muốn | Tại sao quan trọng |
|-----------------|-----------|-------------------|
| Copilot sinh code tự động → mất kiểm soát | Kiểm soát 100% code mình viết | Muốn học thật sự, không chỉ copy |
| Phải tab sang browser để tra docs | Hỏi ngay trong editor, không rời workflow | Tiết kiệm thời gian, giữ focus |
| ChatGPT cho answer mà không dạy | Được hướng dẫn như có mentor | Hiểu sâu concept, không chỉ fix bug |
| Kiến thức học được bị quên | Tích lũy knowledge base cá nhân | Build second brain, review sau |
| Học tech mới chậm | Học siêu nhanh với AI guide | Career growth nhanh hơn |

---

## 🎯 PRODUCT SẼ LÀM ĐƯỢC GÌ

### Core Features

| Feature | Mô tả | Use Case |
|---------|-------|----------|
| **Comment-based Q&A** | Viết `// Q: câu hỏi` → AI trả lời ngay | "TCP socket có những option gì?" |
| **5 Interaction Modes** | Q/S/R/D/E cho mục đích khác nhau | Socratic mode để tự suy luận |
| **Pedagogical Design** | Hướng dẫn, không cho đáp án trực tiếp | Học thật sự thay vì copy-paste |
| **Context-Aware** | Hiểu code xung quanh câu hỏi | Answer phù hợp với context |
| **Incremental Hints** | Gợi ý từng bước nếu chưa hiểu | Như có tutor bên cạnh |
| **Knowledge Tracking** | Lưu mọi Q&A, search được sau | Personal documentation |
| **RAG Codebase** | Hiểu toàn bộ project, không chỉ file | "Authentication ở đâu?" |

### 5 Modes Chi Tiết

```
// Q: Hỏi trực tiếp           → Giải thích rõ ràng + ví dụ
// S: Socratic question       → Hỏi ngược để guide suy luận  
// R: Review this code        → Code review chi tiết
// D: Debug this              → Hướng dẫn debug methodically
// E: Explain concept         → Giải thích sâu khái niệm
```

---

## 🎨 USER WORKFLOW

```
Bạn đang code Go HTTP server
     ↓
Gặp thắc mắc về timeout
     ↓
Viết comment: // Q: HTTP server timeout best practices?
     ↓
Nhấn <leader>ma
     ↓
Floating window hiện giải thích:
  - ReadTimeout vs WriteTimeout
  - Recommended values
  - Graceful shutdown
  - Code example
     ↓
Bạn TỰ VIẾT code dựa trên hiểu biết
     ↓
Knowledge được lưu vào personal docs
```

---

## 🆚 SO SÁNH VỚI COPILOT

| Aspect | GitHub Copilot | AI Code Mentor (Product của bạn) |
|--------|----------------|----------------------------------|
| **Approach** | Generate code for you | Explain concepts to you |
| **Control** | AI viết, bạn accept | Bạn viết 100%, AI guide |
| **Learning** | Ít (copy-paste) | Nhiều (understand deeply) |
| **Interaction** | Autocomplete passive | Comment-based active |
| **Knowledge** | Không lưu | Tích lũy knowledge base |
| **Context** | Current file | Whole project (RAG) |
| **Goal** | Productivity | Learning + Mastery |

---

## 💎 GIÁ TRỊ CỐT LÕI

| Value Proposition | Giải thích |
|-------------------|-----------|
| **Learn, Don't Copy** | Trở thành developer giỏi hơn thay vì output code nhanh hơn |
| **Mentor in Editor** | Như có senior dev ngồi bên hướng dẫn 24/7 |
| **Your Knowledge, Your Pace** | Build knowledge base theo cách bạn học |
| **Context-Aware Teaching** | Không phải generic docs, mà tailored cho project bạn |
| **Open Source** | Free, customizable, privacy-focused |

---

## 🎯 TARGET USERS

| User Segment | Pain Point | How Product Helps |
|--------------|------------|-------------------|
| **Students** | Học chậm, khó hiểu concepts | Socratic mode guide từng bước |
| **Junior Devs** | Thiếu mentor, nhiều thắc mắc | Always-available mentor |
| **Mid-Level** | Học tech mới nhanh | Explain mode cho concepts mới |
| **Senior Devs** | Review code team | Review mode tự động |
| **Solo Developers** | Không có ai hỏi | AI mentor 24/7 |

**Đặc biệt phù hợp**: Sinh viên CS, self-taught devs, devs học tech stack mới

---

## 🚀 MVP FEATURES (Phase 1)

| Must Have | Nice to Have | Future |
|-----------|--------------|--------|
| ✅ Comment-based Q&A | ⏳ Multiple modes | 🔮 RAG codebase |
| ✅ Claude API integration | ⏳ Incremental hints | 🔮 Knowledge graph |
| ✅ Floating window UI | ⏳ Basic knowledge save | 🔮 Team sharing |
| ✅ Context collection | ⏳ Reflection prompts | 🔮 Visual analytics |
| ✅ Keybindings | | 🔮 Obsidian integration |

**MVP Success = Có thể hỏi và nhận câu trả lời hữu ích trong <5s**

---

## 📊 SUCCESS METRICS

| Metric | Target | Measurement |
|--------|--------|-------------|
| Response quality | 80%+ helpful | User survey |
| Response time | <5s | Technical timer |
| Learning speed | 2x faster than docs | Self-reported |
| Daily usage | 10+ questions/day | Analytics |
| Knowledge entries | 50+ in 1 month | Count |
| User satisfaction | 4.5/5 stars | Feedback |

---

## 💭 DESIGN PRINCIPLES

1. **Guide, Don't Give** - Teach to fish, don't give fish
2. **Respect Agency** - User always in control of code
3. **Context is King** - Understand full picture
4. **Incremental Help** - Start subtle, increase if needed
5. **Knowledge Compounds** - Every interaction adds to learning
6. **Fast & Smooth** - Never disrupt coding flow

---

## 🎓 USE CASES CỤ THỂ

### Use Case 1: Học Rust
```rust
// Q: Rust ownership và borrowing work thế nào?
fn process(data: &str) { }
```
→ AI giải thích ownership concepts với examples từ code bạn

### Use Case 2: Debug Performance
```go
// D: Function này chậm, có thể optimize không?
func processData(items []Item) []Result { ... }
```
→ AI guide cách profile, identify bottleneck

### Use Case 3: Code Review
```python
// R: Review function này
def calculate_total(prices, tax_rate=0.1):
    return sum(prices) * (1 + tax_rate)
```
→ AI point out edge cases, naming, type hints

### Use Case 4: Socratic Learning
```js
// S: Tại sao Promise.all tốt hơn sequential await?
```
→ AI hỏi ngược: "Nếu có 10 API calls độc lập, sequential mất bao lâu?"

### Use Case 5: Deep Explanation
```typescript
// E: Closure trong JavaScript
function outer() { ... }
```
→ AI giải thích closure từ cơ bản đến nâng cao với examples

---

## 🎨 MOCKUP UI

```
┌─────────────────────────────────────────────────┐
│ editor.go                                  [x] │
├─────────────────────────────────────────────────┤
│                                                 │
│  func StartServer(port int) {                  │
│      // Q: HTTP server timeout best practices? │ ← User viết
│      srv := &http.Server{                      │
│          Addr: fmt.Sprintf(":%d", port),       │
│      }                                          │
│  }                                              │
│                                                 │
│  [User nhấn <leader>ma]                        │
│                                                 │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  🧑‍🏫 Code Mentor                           [x] │
├─────────────────────────────────────────────────┤
│                                                 │
│  ❓ Question:                                   │
│  HTTP server timeout best practices?           │
│                                                 │
│  💡 Answer:                                     │
│                                                 │
│  For production HTTP servers in Go, you should │
│  configure 3 key timeouts:                     │
│                                                 │
│  1. **ReadTimeout**: Time to read request      │
│     ```go                                       │
│     ReadTimeout: 10 * time.Second              │
│     ```                                         │
│     Prevents slow clients from holding conns   │
│                                                 │
│  2. **WriteTimeout**: Time to write response   │
│     Common values: 10-30s depending on payload │
│                                                 │
│  3. **IdleTimeout**: Keep-alive timeout        │
│     Recommended: 120s                           │
│                                                 │
│  [q] Close  [y] Copy  [n] Next hint            │
└─────────────────────────────────────────────────┘
```

---

## ✨ TẠI SAO ĐÂY LÀ Ý TƯỞNG TỐT

1. **Unique Position**: Không ai focus vào teaching trong editor
2. **Real Need**: Bạn tự muốn dùng → product-market fit
3. **Technical Feasible**: Đã có precedents (wtf.nvim, CS50.ai)
4. **Scalable**: Start personal → share với GDSC → open source community
5. **Portfolio Value**: Impressive project cho CV
6. **Learning Vehicle**: Học nhiều skills trong quá trình build

---

## 🎯 1-SENTENCE PITCH

> **"GitHub Copilot viết code cho bạn, AI Code Mentor dạy bạn viết code—giúp bạn kiểm soát 100% và học nhanh 2x thông qua comment-based interaction ngay trong Neovim."**

---

## 🚀 IMMEDIATE NEXT STEP

1. Clone wtf.nvim và gp.nvim
2. Đọc source code 2-3 giờ
3. Write Hello World plugin
4. Test với câu hỏi thật: `// Q: What is this?`
5. Demo cho 1-2 người GDSC
6. Iterate based on feedback

**START TODAY! 🎉**
