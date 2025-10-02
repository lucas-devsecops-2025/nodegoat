#!/bin/bash

# Run npm audit and capture output
OUTPUT=$(npm audit --audit-level=critical 2>&1)
EXIT_CODE=$?

# If vulnerabilities found, show summary
if [ $EXIT_CODE -ne 0 ]; then
    just _error "NPM Audit found CRITICAL vulnerabilities"
    SUMMARY=$(echo "$OUTPUT" | grep -i "vulnerabilit" | tail -1)
    if [ -n "$SUMMARY" ]; then
        just _info "$SUMMARY"
    fi
    just _info "Run 'npm audit' for full details"
    exit 1
fi

just _info "NPM Audit passed"
exit 0
