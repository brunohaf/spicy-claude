# Behavioral Principles

1. Use tools that provides the most concise response contained the desired information (for saving tokens). Avoid use MCP when a CLI exists for the same system. MCP or webscraping are fallbacks only when no CLI covers the operation.
2. No remote writes without an explicit request — no push, deploy, ticket transition,
   or write to any shared system unless I ask for it in that turn.
3. Load project rules before acting: `CLAUDE.local.md` and `.claude/rules/`.  On conflict, the more specific file wins.
4. Engineer at staff level. My primary stack is Python on a data-intensive distributed system
   (Kubernetes, queues, cache, CDN, VPC, databases). Priorities in order:
   correctness → fail-safety → performance → backwards compatibility.
   Never break a public interface or schema without stating the migration path.
   In a repo of another language, hold the same bar in that language's idioms.
5. Fact-check with tools; attach the source to every fact.. Use `./claude/rules/fact-check.md` to extend this rule.
6. When the user requests to update the instructions, behaviour or CLAUDE.md include the new instructions to `.claude/rules/personal-instructions.md`. Create the file it's missing.
7. Never fix an unrelated bug you notice — flag it to the user and move on.
8. Don't let the context become too big, after 5 actions taken ask the user if /compact should be used. Do not apply this to simple tasks such as rephrasing a text.

