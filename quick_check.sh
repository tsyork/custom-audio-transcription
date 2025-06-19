#!/bin/bash

# Quick Security Check - Run before any git operations
# Fast check for the most critical security issues

echo "🔒 Quick Security Check"
echo "======================"

ISSUES=0

# Check for critical file extensions in git staging area
echo "🔍 Checking staged files..."
if [ -d ".git" ]; then
    staged_files=$(git diff --cached --name-only 2>/dev/null || true)
    
    if [ -n "$staged_files" ]; then
        echo "Staged files:"
        for file in $staged_files; do
            echo "   $file"
            
            case "$file" in
                *.pem|*.key|*credentials.json|*.env|config/spot-fleet-config.json)
                    echo "❌ CRITICAL: Sensitive file staged: $file"
                    ISSUES=$((ISSUES + 1))
                    ;;
                config/*)
                    echo "⚠️  Config file - verify no secrets: $file"
                    ;;
                *)
                    echo "✅ Safe file: $file"
                    ;;
            esac
        done
    else
        echo "✅ No files staged"
    fi
else
    echo "⚠️  Not a git repository"
fi

# Quick pattern check in staged files
echo ""
echo "🔍 Quick pattern scan..."
if [ -d ".git" ] && [ -n "$staged_files" ]; then
    for file in $staged_files; do
        if [ -f "$file" ]; then
            # Check for obvious secrets
            if grep -q "AKIA[0-9A-Z]\{16\}" "$file" 2>/dev/null; then
                echo "❌ AWS Access Key found in $file"
                ISSUES=$((ISSUES + 1))
            fi
            
            if grep -q "-----BEGIN.*PRIVATE KEY-----" "$file" 2>/dev/null; then
                echo "❌ Private key found in $file"
                ISSUES=$((ISSUES + 1))
            fi
            
            if grep -q "\"type\": \"service_account\"" "$file" 2>/dev/null; then
                echo "❌ Google service account found in $file"
                ISSUES=$((ISSUES + 1))
            fi
        fi
    done
fi

echo ""
if [ $ISSUES -eq 0 ]; then
    echo "✅ QUICK CHECK PASSED - Safe to proceed"
    echo "💡 Run ./security_audit.sh for comprehensive scan"
else
    echo "❌ ISSUES FOUND: $ISSUES"
    echo "🛑 DO NOT PUSH - Fix issues first"
    echo "Run ./security_audit.sh for detailed analysis"
fi

exit $ISSUES
