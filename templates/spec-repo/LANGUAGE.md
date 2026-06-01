# LANGUAGE — shared vocabulary

| Term | Definition |
|------|------------|
| **Module** | A unit with a public interface and a hidden implementation. |
| **Interface** | The surface a caller depends on. |
| **Seam** | A point where behaviour can be substituted without editing callers. |
| **Depth** | Ratio of hidden complexity to interface size; deeper is better. |
| **Leverage** | How much downstream simplification a module provides per unit of its own complexity. |
| **Locality** | All code touched by one change lives near each other. |
| **Deletion test** | Could this module be deleted and rewritten in isolation? If no, it lacks depth. |
