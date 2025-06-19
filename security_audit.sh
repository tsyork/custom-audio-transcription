#!/bin/bash

# Security Audit Script for Custom Audio Transcription Project
# Scans for sensitive information before GitHub push

set -e

echo "🔒 SECURITY AUDIT - Custom Audio Transcription Project"
echo "====================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ISSUES_FOUND=0
PROJECT_DIR="."

echo -e "${BLUE}📂 Scanning project directory: $(pwd)${NC}"
echo ""

# ===== 1. CHECK FOR SENSITIVE FILE EXTENSIONS =====
echo -e "${BLUE}🔍 1. Checking for sensitive file extensions...${NC}"

sensitive_extensions=("*.pem" "*.key" "*.p12" "*.pfx" "*.env" "*.credentials")
for ext in "${sensitive_extensions[@]}"; do
    files=$(find "$PROJECT_DIR" -name "$ext" -not -path "./.git/*" 2>/dev/null || true)
    if [ -n "$files" ]; then
        # Check if files are gitignored
        gitignored_files=""
        tracked_files=""
        
        for file in $files; do
            if [ -d ".git" ] && git check-ignore "$file" >/dev/null 2>&1; then
                gitignored_files="$gitignored_files$file (gitignored)\n"
            else
                tracked_files="$tracked_files$file\n"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        done
        
        if [ -n "$tracked_files" ]; then
            echo -e "${RED}❌ Found sensitive files that are NOT gitignored:${NC}"
            echo -e "$tracked_files"
        fi
        
        if [ -n "$gitignored_files" ]; then
            echo -e "${GREEN}✅ Found sensitive files that are properly gitignored:${NC}"
            echo -e "$gitignored_files"
        fi
    fi
done

# Special handling for JSON files (some are safe, some aren't)
json_files=$(find "$PROJECT_DIR" -name "*.json" -not -path "./.git/*" 2>/dev/null || true)
if [ -n "$json_files" ]; then
    echo -e "${BLUE}🔍 Checking JSON files specifically...${NC}"
    
    for file in $json_files; do
        # Check if it's a known sensitive file
        case "$(basename "$file")" in
            credentials.json|*service-account*.json|*serviceaccount*.json)
                if [ -d ".git" ] && git check-ignore "$file" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ $file (sensitive, but gitignored)${NC}"
                else
                    echo -e "${RED}❌ $file (sensitive and NOT gitignored!)${NC}"
                    ISSUES_FOUND=$((ISSUES_FOUND + 1))
                fi
                ;;
            spot-fleet-config.json)
                if [ -d ".git" ] && git check-ignore "$file" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ $file (sensitive, but gitignored)${NC}"
                else
                    echo -e "${RED}❌ $file (sensitive and NOT gitignored!)${NC}"
                    ISSUES_FOUND=$((ISSUES_FOUND + 1))
                fi
                ;;
            *.template.json|package.json|package-lock.json)
                echo -e "${GREEN}✅ $file (safe JSON file)${NC}"
                ;;
            *)
                # Check if it's gitignored
                if [ -d ".git" ] && git check-ignore "$file" >/dev/null 2>&1; then
                    echo -e "${YELLOW}⚠️  $file (gitignored, verify contents are safe)${NC}"
                else
                    echo -e "${YELLOW}⚠️  $file (verify contents are safe)${NC}"
                fi
                ;;
        esac
    done
fi

# ===== 2. CHECK FOR SENSITIVE CONTENT PATTERNS =====
echo -e "${BLUE}🔍 2. Scanning file contents for sensitive patterns...${NC}"

# List of sensitive patterns to search for
declare -A patterns=(
    ["AWS Access Key"]="AKIA[0-9A-Z]{16}"
    ["AWS Secret Key"]="[0-9a-zA-Z/+]{40}"
    ["Private Key"]="-----BEGIN (RSA |)PRIVATE KEY-----"
    ["Google Service Account"]="\"type\": \"service_account\""
    ["AWS Account ID"]="[0-9]{12}"
    ["SSH Private Key"]="-----BEGIN OPENSSH PRIVATE KEY-----"
    ["API Key"]="(api[_-]?key|apikey).*['\"][0-9a-zA-Z]{32,}['\"]"
    ["Password"]="(password|passwd|pwd).*['\"][^'\"]{8,}['\"]"
    ["Secret"]="(secret|token).*['\"][0-9a-zA-Z]{16,}['\"]"
    ["Email with sensitive domains"]="[a-zA-Z0-9._%+-]+@(gmail|yahoo|hotmail|outlook)\.(com|net|org)"
)

# Scan text files for patterns
text_files=$(find "$PROJECT_DIR" -type f \( -name "*.py" -o -name "*.sh" -o -name "*.md" -o -name "*.txt" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.conf" -o -name "*.config" \) -not -path "./.git/*" 2>/dev/null || true)

for file in $text_files; do
    if [ -f "$file" ]; then
        echo -e "${YELLOW}   Scanning: $file${NC}"
        
        for pattern_name in "${!patterns[@]}"; do
            pattern="${patterns[$pattern_name]}"
            matches=$(grep -P "$pattern" "$file" 2>/dev/null || true)
            if [ -n "$matches" ]; then
                echo -e "${RED}❌ Found $pattern_name in $file:${NC}"
                echo -e "${RED}   $matches${NC}"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        done
    fi
done

# ===== 3. CHECK .GITIGNORE COVERAGE =====
echo -e "${BLUE}🔍 3. Checking .gitignore coverage...${NC}"

if [ ! -f ".gitignore" ]; then
    echo -e "${RED}❌ No .gitignore file found!${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "${GREEN}✅ .gitignore file exists${NC}"
    
    # Check if sensitive directories/files are ignored
    critical_ignores=("config/credentials.json" "config/*.pem" "*.pem" "credentials.json" "logs/" "temp_audio/")
    
    for ignore_pattern in "${critical_ignores[@]}"; do
        if grep -q "$ignore_pattern" .gitignore; then
            echo -e "${GREEN}✅ $ignore_pattern is gitignored${NC}"
        else
            echo -e "${YELLOW}⚠️  $ignore_pattern should be added to .gitignore${NC}"
        fi
    done
fi

# ===== 4. CHECK GIT STATUS =====
echo -e "${BLUE}🔍 4. Checking git status for staged sensitive files...${NC}"

if [ -d ".git" ]; then
    staged_files=$(git diff --cached --name-only 2>/dev/null || true)
    if [ -n "$staged_files" ]; then
        echo "Staged files:"
        for file in $staged_files; do
            echo "   $file"
            
            # Check if staged file contains sensitive patterns
            if [ -f "$file" ]; then
                case "$file" in
                    *.pem|*.key|*credentials*|*.env)
                        echo -e "${RED}❌ CRITICAL: Sensitive file is staged for commit: $file${NC}"
                        ISSUES_FOUND=$((ISSUES_FOUND + 1))
                        ;;
                    config/*)
                        echo -e "${YELLOW}⚠️  Config file staged - verify it contains no secrets: $file${NC}"
                        ;;
                esac
            fi
        done
    else
        echo -e "${GREEN}✅ No files currently staged${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Not a git repository${NC}"
fi

# ===== 5. CHECK FOR HARDCODED VALUES =====
echo -e "${BLUE}🔍 5. Checking for hardcoded sensitive values...${NC}"

# Specific checks for this project
echo "   Checking Python scripts for hardcoded values..."

python_files=$(find "$PROJECT_DIR" -name "*.py" -not -path "./.git/*" 2>/dev/null || true)
for file in $python_files; do
    if [ -f "$file" ]; then
        # Check for hardcoded project IDs, bucket names, etc.
        hardcoded_checks=(
            "podcast-transcription-462218"
            "ai_knowledgebase" 
            "custom-transcription"
            "136Nmn3gJe0DPVh8p4vUl3oD4-qDNRySh"
        )
        
        for check in "${hardcoded_checks[@]}"; do
            if grep -q "$check" "$file"; then
                echo -e "${YELLOW}⚠️  Found hardcoded value '$check' in $file${NC}"
                echo -e "${YELLOW}   Consider making this configurable${NC}"
            fi
        done
    fi
done

# ===== 6. CHECK FILE PERMISSIONS =====
echo -e "${BLUE}🔍 6. Checking file permissions...${NC}"

# Check for overly permissive files
permissive_files=$(find "$PROJECT_DIR" -type f -perm -004 -not -path "./.git/*" 2>/dev/null || true)
if [ -n "$permissive_files" ]; then
    echo -e "${YELLOW}⚠️  Files with world-readable permissions:${NC}"
    ls -la $permissive_files
fi

# ===== 7. TEMPLATE FILE CHECK =====
echo -e "${BLUE}🔍 7. Checking template files are present...${NC}"

template_files=("config/spot-fleet-config.template.json")
for template in "${template_files[@]}"; do
    if [ -f "$template" ]; then
        echo -e "${GREEN}✅ Template file exists: $template${NC}"
        
        # Check template doesn't contain real values
        if grep -q "YOUR_" "$template"; then
            echo -e "${GREEN}✅ Template contains placeholder values${NC}"
        else
            echo -e "${YELLOW}⚠️  Template may contain real values instead of placeholders${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Template file missing: $template${NC}"
    fi
done

# ===== 8. FINAL RECOMMENDATIONS =====
echo ""
echo -e "${BLUE}📋 FINAL SECURITY REPORT${NC}"
echo "========================"

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}🎉 SECURITY AUDIT PASSED!${NC}"
    echo -e "${GREEN}✅ No sensitive information will be pushed to GitHub${NC}"
    echo -e "${GREEN}✅ All sensitive files are properly gitignored${NC}"
    echo -e "${GREEN}✅ Safe to push to GitHub${NC}"
else
    echo -e "${RED}🚨 SECURITY ISSUES FOUND: $ISSUES_FOUND${NC}"
    echo -e "${RED}❌ Some sensitive files are NOT properly gitignored${NC}"
    echo -e "${RED}❌ DO NOT push to GitHub until issues are resolved${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Recommended actions:${NC}"
    echo "1. Add sensitive files to .gitignore"
    echo "2. Remove sensitive files from git tracking if already added"
    echo "3. Replace hardcoded secrets with environment variables"
    echo "4. Use template files with placeholder values"
    echo "5. Run this audit again before pushing"
fi

echo ""
echo -e "${BLUE}🛡️  Security Best Practices:${NC}"
echo "• Sensitive files on filesystem are OK if they're gitignored"
echo "• Always run this audit before git push"
echo "• Use template files for configuration"
echo "• Store secrets in environment variables or external files"
echo "• Regularly rotate access keys and credentials"
echo "• Monitor your repositories for accidental credential exposure"

echo ""
echo -e "${BLUE}🔍 Manual Review Checklist:${NC}"
echo "• Review all staged files: git diff --cached"
echo "• Check .gitignore covers all sensitive patterns"
echo "• Verify template files use placeholders"
echo "• Confirm no real credentials in any committed files"
echo "• Files can exist locally if they're properly gitignored"

exit $ISSUES_FOUND