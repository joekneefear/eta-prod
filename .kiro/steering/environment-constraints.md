# Environment Constraints

This workspace runs in a restricted environment where certain tools are not available.

## Unavailable Tools

The following tools **cannot** be installed or invoked in this environment:

- **Maven** (`mvn`, `mvnw`) — Java build and test runner
- **Java** (`java`, `javac`) — JDK/JRE runtime
- **Node.js** (`node`, `npm`, `npx`) — JavaScript runtime and package manager
- **Python** (`python`, `python3`, `pip`) — Python runtime and package manager

## Impact on Development Tasks

### What Cannot Be Done Locally
- Backend Java tests (JUnit, jqwik) cannot be compiled or executed
- Frontend Angular tests (Karma, Jasmine) cannot be run
- Python test suites cannot be executed
- Any task requiring `mvn test`, `npm test`, `ng test`, `pytest`, or similar cannot be verified by the agent locally

### What the Agent Should Do Instead

**For Checkpoint Tasks with Tests:**
- Skip execution and note that tests must be run manually in a local environment
- Confirm the code is correct through static analysis instead
- Provide clear instructions for the user to run tests locally

**For Code-Writing Tasks:**
- Produce correct, complete code
- Verify correctness through static analysis:
  - Reading and reviewing the code logic
  - Checking type safety and syntax
  - Reviewing API usage against library documentation
  - Analyzing against requirements and design specifications
- Do NOT attempt to install or locate unavailable tools

**For Verification:**
- Use code review and logical analysis instead of execution
- Check that code follows project patterns and conventions
- Verify that implementation matches the design document

## Guidelines for Task Execution

1. **Never attempt** to install Python, Node.js, Java, or Maven
2. **Always check** if a task requires execution before committing to it
3. **Always document** when tests cannot be run locally and must be run manually
4. **Always provide** clear instructions for running tests in a local environment
5. **Always verify** code correctness through static analysis and code review

## Related Documentation

- Design and requirements documents are available for reference
- Test code should follow patterns established in existing test files
- Verification is done through code review against specifications
