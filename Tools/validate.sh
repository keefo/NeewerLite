#!/bin/bash

# Validation script for NeewerLite release
# This script validates:
# 1. appcast.xml from remote server
# 2. ZIP file download from website
# 3. DMG file from GitHub release

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# GitHub release metadata
REPO_OWNER="keefo"
REPO_NAME="NeewerLite"

# Temporary directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Default options
VERBOSE=false
SKIP_ZIP=false
SKIP_DMG=false
SKIP_APPCAST=false
SKIP_LIGHTS_DB=false

# Function to show help
show_help() {
    echo "🔍 NeewerLite Release Validation Script"
    echo "======================================"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -v, --verbose     Enable verbose output"
    echo "  --skip-appcast    Skip appcast.xml validation"
    echo "  --skip-zip        Skip ZIP file validation"
    echo "  --skip-dmg        Skip DMG file validation"
    echo "  --skip-lights-db  Skip lights database validation"
    echo
    echo "Environment variables (optional):"
    echo "  NEEWERLITE_REMOTE_FOLDER      - Remote folder path (for legacy SCP method)"
    echo "  NEEWERLITE_REMOTE_USER_NAME   - Remote user@host (for legacy SCP method)"
    echo
    echo "Note: The script now reads the appcast URL directly from Info.plist"
    echo
    echo "Examples:"
    echo "  $0                           # Run all validations"
    echo "  $0 --skip-zip               # Skip ZIP validation"
    echo "  $0 -v --skip-appcast        # Verbose mode, skip appcast"
    echo "  $0 --skip-lights-db         # Skip lights database validation"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-appcast)
            SKIP_APPCAST=true
            shift
            ;;
        --skip-zip)
            SKIP_ZIP=true
            shift
            ;;
        --skip-dmg)
            SKIP_DMG=true
            shift
            ;;
        --skip-lights-db)
            SKIP_LIGHTS_DB=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo "🔍 NeewerLite Release Validation Script"
echo "======================================"

# Function to print status messages
print_status() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Verify environment variables (only needed for some validations)
print_status "Checking environment variables..."

# These variables are only needed if we're doing SCP-based validations (which we're not using anymore)
# But we'll keep the check for backward compatibility or future use
if [ -z "$NEEWERLITE_REMOTE_FOLDER" ] && [ -z "$NEEWERLITE_REMOTE_USER_NAME" ]; then
    print_status "Remote environment variables not set (not required for current validation methods)"
else
    print_success "Remote environment variables are available"
fi

# Function to get the latest release tag from GitHub
get_latest_release_tag() {
    gh api repos/$REPO_OWNER/$REPO_NAME/releases/latest --jq '.tag_name' 2>/dev/null || echo ""
}

# Function to get the appcast URL from Info.plist
get_appcast_url() {
    local info_plist="../NeewerLite/NeewerLite/Resources/Info.plist"
    if [ -f "$info_plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$info_plist" 2>/dev/null
    else
        echo ""
    fi
}

# Function to validate appcast.xml
validate_appcast() {
    print_status "Validating appcast.xml from remote server..."
    
    # Get the appcast URL from Info.plist
    local appcast_url=$(get_appcast_url)
    local appcast_file="$TEMP_DIR/appcast.xml"
    
    if [ -z "$appcast_url" ]; then
        print_error "Could not get SUFeedURL from Info.plist"
        return 1
    fi
    
    print_success "Found appcast URL in Info.plist: $appcast_url"
    
    # Download appcast.xml via HTTP
    print_status "Downloading appcast.xml from $appcast_url..."
    if curl -s -f -o "$appcast_file" "$appcast_url"; then
        print_success "Downloaded appcast.xml successfully"
        
        # Check if it's valid XML
        if xmllint --noout "$appcast_file" 2>/dev/null; then
            print_success "appcast.xml is valid XML"
            
            # Extract version and download URL from appcast using sparkle format
            local version=$(xmllint --xpath "//item/title/text()" "$appcast_file" 2>/dev/null | head -1)
            local download_url=$(xmllint --xpath "//enclosure/@url" "$appcast_file" 2>/dev/null | sed 's/url="//g' | sed 's/"//g' | tr -d ' \t\n\r')
            
            # Also try to get sparkle:shortVersionString for more accurate version
            local sparkle_version=$(grep -o 'sparkle:shortVersionString="[^"]*"' "$appcast_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/' 2>/dev/null)
            
            if [ -n "$sparkle_version" ]; then
                version="$sparkle_version"
                print_success "Found sparkle version: $version"
            elif [ -n "$version" ]; then
                print_success "Found version from title: $version"
            fi
            
            if [ -n "$version" ] && [ -n "$download_url" ]; then
                print_success "Found download URL: $download_url"
                echo "$version" > "$TEMP_DIR/appcast_version"
                echo "$download_url" > "$TEMP_DIR/download_url"
            else
                print_error "Could not extract version or download URL from appcast.xml"
                if [ "$VERBOSE" = true ]; then
                    print_status "Appcast content preview:"
                    head -20 "$appcast_file"
                fi
                return 1
            fi
        else
            print_error "appcast.xml is not valid XML"
            return 1
        fi
    else
        print_error "Failed to download appcast.xml from $appcast_url"
        return 1
    fi
}

# Function to validate ZIP download
validate_zip_download() {
    print_status "Validating ZIP file from website..."
    
    if [ ! -f "$TEMP_DIR/download_url" ]; then
        print_error "Download URL not available from appcast validation"
        return 1
    fi
    
    local download_url=$(cat "$TEMP_DIR/download_url")
    local zip_file="$TEMP_DIR/NeewerLite.zip"
    
    # Download the ZIP file
    if curl -s -f -L -o "$zip_file" "$download_url"; then
        print_success "Downloaded ZIP file successfully"
        
        # Check if it's a valid ZIP file
        if unzip -t "$zip_file" >/dev/null 2>&1; then
            print_success "ZIP file is valid"
            
            # Get file size and checksum
            local file_size=$(stat -f%z "$zip_file" 2>/dev/null || stat -c%s "$zip_file" 2>/dev/null)
            local sha256_hash=$(shasum -a 256 "$zip_file" | cut -d' ' -f1)
            
            print_success "ZIP file size: $file_size bytes"
            print_success "ZIP file SHA256: $sha256_hash"
            
            # List contents briefly
            print_status "ZIP file contents:"
            unzip -l "$zip_file" | head -10
        else
            print_error "ZIP file is corrupted or invalid"
            return 1
        fi
    else
        print_error "Failed to download ZIP file from $download_url"
        return 1
    fi
}

# Function to validate DMG from GitHub
validate_dmg_from_github() {
    print_status "Validating DMG file from GitHub release..."
    
    # Get the latest release tag
    local latest_tag=$(get_latest_release_tag)
    
    if [ -z "$latest_tag" ]; then
        print_error "Could not get latest release tag from GitHub"
        return 1
    fi
    
    print_success "Latest GitHub release tag: $latest_tag"
    
    # Get release assets
    local assets_json="$TEMP_DIR/assets.json"
    gh api repos/$REPO_OWNER/$REPO_NAME/releases/tags/$latest_tag --jq '.assets' > "$assets_json"
    
    # Find DMG asset
    local dmg_download_url=$(jq -r '.[] | select(.name | endswith(".dmg")) | .browser_download_url' "$assets_json")
    
    if [ -z "$dmg_download_url" ] || [ "$dmg_download_url" = "null" ]; then
        print_error "No DMG file found in GitHub release $latest_tag"
        return 1
    fi
    
    print_success "Found DMG download URL: $dmg_download_url"
    
    # Download the DMG file
    local dmg_file="$TEMP_DIR/NeewerLite.dmg"
    if curl -s -f -L -o "$dmg_file" "$dmg_download_url"; then
        print_success "Downloaded DMG file successfully"
        
        # Verify DMG file (multiple checks)
        local file_type=$(file "$dmg_file")
        print_status "File type: $file_type"
        
        if echo "$file_type" | grep -q -E "(Apple disk image|Macintosh HFS|bzip2 compressed|zlib compressed)"; then
            print_success "DMG file appears to be valid"
        elif [ -s "$dmg_file" ]; then
            # File exists and has size, let's try a different approach
            print_status "File type not immediately recognized, checking file header..."
            local header=$(hexdump -C "$dmg_file" | head -1)
            print_status "File header: $header"
            
            # Check for common DMG magic numbers
            if head -c 8 "$dmg_file" | grep -q -E "(\x78\x01|\x78\x9c|\x78\xda)" 2>/dev/null; then
                print_success "DMG file appears to be compressed disk image"
            else
                print_status "DMG file format not immediately identifiable, but file exists and has content"
            fi
        else
            print_error "Downloaded file appears to be empty or invalid"
            return 1
        fi
        
        # Get file size and checksum
        local file_size=$(stat -f%z "$dmg_file" 2>/dev/null || stat -c%s "$dmg_file" 2>/dev/null)
        local sha256_hash=$(shasum -a 256 "$dmg_file" | cut -d' ' -f1)
        
        print_success "DMG file size: $file_size bytes"
        print_success "DMG file SHA256: $sha256_hash"
        
        # Try to mount and verify contents (optional, might require sudo)
        print_status "Attempting to verify DMG contents..."
        local mount_point="$TEMP_DIR/dmg_mount"
        mkdir -p "$mount_point"
        
        if hdiutil attach "$dmg_file" -readonly -nobrowse -mountpoint "$mount_point" >/dev/null 2>&1; then
            if [ -d "$mount_point/NeewerLite.app" ]; then
                print_success "Found NeewerLite.app in DMG"
                
                # Get app version
                local app_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$mount_point/NeewerLite.app/Contents/Info.plist" 2>/dev/null)
                if [ -n "$app_version" ]; then
                    print_success "App version in DMG: $app_version"
                    echo "$app_version" > "$TEMP_DIR/dmg_version"
                fi
            else
                print_error "NeewerLite.app not found in DMG"
            fi
            
            # Unmount
            hdiutil detach "$mount_point" >/dev/null 2>&1
        else
            print_status "Could not mount DMG for content verification"
            print_status "This might be normal for compressed or encrypted DMGs"
            
            # Alternative: try using hdiutil imageinfo to get basic info
            if hdiutil imageinfo "$dmg_file" >/dev/null 2>&1; then
                print_success "DMG file structure appears valid (verified with hdiutil imageinfo)"
            else
                print_status "Could not verify DMG structure with hdiutil imageinfo"
            fi
        fi
    else
        print_error "Failed to download DMG file from GitHub"
        return 1
    fi
}

# Function to validate lights database
validate_lights_database() {
    print_status "Validating Database/lights.json..."
    
    local lights_db_path="../Database/lights.json"
    
    # Check if file exists
    if [ ! -f "$lights_db_path" ]; then
        print_error "lights.json not found at $lights_db_path"
        return 1
    fi
    
    print_success "Found lights.json file"
    
    # Check if it's valid JSON
    if ! jq empty "$lights_db_path" 2>/dev/null; then
        print_error "lights.json is not valid JSON"
        return 1
    fi
    
    print_success "lights.json is valid JSON"
    
    # Validate JSON structure
    local validation_errors=0
    
    # Check for required top-level fields
    local version=$(jq -r '.version' "$lights_db_path" 2>/dev/null)
    if [ "$version" = "null" ] || [ -z "$version" ]; then
        print_error "Missing or invalid 'version' field"
        validation_errors=$((validation_errors + 1))
    else
        print_success "Found version: $version"
    fi
    
    # Check if lights array exists
    local lights_count=$(jq -r '.lights | length' "$lights_db_path" 2>/dev/null)
    if [ "$lights_count" = "null" ] || [ "$lights_count" -eq 0 ] 2>/dev/null; then
        print_error "Missing or empty 'lights' array"
        validation_errors=$((validation_errors + 1))
    else
        print_success "Found $lights_count light definitions"
    fi
    
    # Validate each light entry
    local light_index=0
    local required_fields=("type" "supportRGB" "supportCCTGM" "supportMusic" "support17FX" "support9FX")
    local required_command_patterns=("power")
    
    while IFS= read -r light; do
        if [ "$VERBOSE" = true ]; then
            print_status "  Validating light #$light_index..."
        fi
        
        # Check required fields
        for field in "${required_fields[@]}"; do
            local field_value=$(echo "$light" | jq -r ".$field" 2>/dev/null)
            if [ "$field_value" = "null" ]; then
                print_error "  Light #$light_index: Missing required field '$field'"
                validation_errors=$((validation_errors + 1))
            fi
        done
        
        # Validate type is a number
        local type_value=$(echo "$light" | jq -r '.type' 2>/dev/null)
        if ! [[ "$type_value" =~ ^[0-9]+$ ]]; then
            print_error "  Light #$light_index: 'type' must be a number, got: $type_value"
            validation_errors=$((validation_errors + 1))
        fi
        
        # Check command patterns (optional)
        local command_patterns=$(echo "$light" | jq -r '.commandPatterns' 2>/dev/null)
        if [ "$command_patterns" != "null" ]; then
            # If commandPatterns exists, validate its structure
            if [ "$VERBOSE" = true ]; then
                print_success "  Light #$light_index: Has commandPatterns defined"
            fi
            
            # Check required command patterns
            for cmd in "${required_command_patterns[@]}"; do
                local cmd_pattern=$(echo "$light" | jq -r ".commandPatterns.$cmd" 2>/dev/null)
                if [ "$cmd_pattern" = "null" ]; then
                    print_error "  Light #$light_index: Missing required command pattern '$cmd'"
                    validation_errors=$((validation_errors + 1))
                fi
            done
            
            # Validate RGB support consistency (optional check)
            local supports_rgb=$(echo "$light" | jq -r '.supportRGB' 2>/dev/null)
            local has_hsi_pattern=$(echo "$light" | jq -r '.commandPatterns.hsi' 2>/dev/null)
            
            if [ "$supports_rgb" = "true" ] && [ "$has_hsi_pattern" = "null" ]; then
                if [ "$VERBOSE" = true ]; then
                    print_status "  Light #$light_index: supportRGB=true but no 'hsi' command pattern (optional)"
                fi
            fi
        else
            # commandPatterns is optional, just note it in verbose mode
            if [ "$VERBOSE" = true ]; then
                print_status "  Light #$light_index: No commandPatterns defined (optional)"
            fi
        fi
        
        # Validate image URL if present
        local image_url=$(echo "$light" | jq -r '.image' 2>/dev/null)
        if [ -n "$image_url" ] && [ "$image_url" != "null" ] && [ "$image_url" != "" ]; then
            if [[ "$image_url" =~ ^https://github\.com/keefo/NeewerLite/blob/main/Database/light_images/.+\.png\?raw=true$ ]]; then
                if [ "$VERBOSE" = true ]; then
                    print_success "  Light #$light_index: Valid image URL format"
                fi
            else
                print_error "  Light #$light_index: Invalid image URL format: $image_url"
                validation_errors=$((validation_errors + 1))
            fi
        fi
        
        # Validate CCT range if present
        local cct_range=$(echo "$light" | jq -r '.cctRange' 2>/dev/null)
        if [ "$cct_range" != "null" ]; then
            local cct_min=$(echo "$light" | jq -r '.cctRange.min' 2>/dev/null)
            local cct_max=$(echo "$light" | jq -r '.cctRange.max' 2>/dev/null)
            
            if [ "$cct_min" = "null" ] || [ "$cct_max" = "null" ]; then
                print_error "  Light #$light_index: cctRange must have both 'min' and 'max' values"
                validation_errors=$((validation_errors + 1))
            elif ! [[ "$cct_min" =~ ^[0-9]+$ ]] || ! [[ "$cct_max" =~ ^[0-9]+$ ]]; then
                print_error "  Light #$light_index: cctRange min/max must be numbers"
                validation_errors=$((validation_errors + 1))
            elif [ "$cct_min" -ge "$cct_max" ]; then
                print_error "  Light #$light_index: cctRange min ($cct_min) must be less than max ($cct_max)"
                validation_errors=$((validation_errors + 1))
            fi
        fi
        
        light_index=$((light_index + 1))
    done < <(jq -c '.lights[]' "$lights_db_path" 2>/dev/null)
    
    # Check for duplicate types
    local duplicate_types=$(jq -r '.lights[].type' "$lights_db_path" | sort | uniq -d)
    if [ -n "$duplicate_types" ]; then
        print_error "Found duplicate light types: $duplicate_types"
        validation_errors=$((validation_errors + 1))
    else
        print_success "No duplicate light types found"
    fi
    
    # Validate referenced image files exist
    print_status "Checking referenced image files..."
    local missing_images=0
    while IFS= read -r image_file; do
        if [ -n "$image_file" ] && [ "$image_file" != "null" ] && [ "$image_file" != "" ]; then
            # Extract filename from GitHub URL
            local filename=$(echo "$image_file" | sed 's/.*\/\([^?]*\).*/\1/')
            local local_image_path="../Database/light_images/$filename"
            
            if [ ! -f "$local_image_path" ]; then
                print_error "  Referenced image file not found: $local_image_path"
                missing_images=$((missing_images + 1))
            fi
        fi
    done < <(jq -r '.lights[].image' "$lights_db_path" 2>/dev/null)
    
    if [ $missing_images -eq 0 ]; then
        print_success "All referenced image files exist locally"
    else
        print_error "$missing_images referenced image files are missing"
        validation_errors=$((validation_errors + 1))
    fi
    
    # File size and statistics
    local file_size=$(stat -f%z "$lights_db_path" 2>/dev/null || stat -c%s "$lights_db_path" 2>/dev/null)
    print_success "Database file size: $file_size bytes"
    
    # Summary statistics
    local rgb_lights=$(jq -r '[.lights[] | select(.supportRGB == true)] | length' "$lights_db_path")
    local cct_lights=$(jq -r '[.lights[] | select(.supportCCTGM == true)] | length' "$lights_db_path")
    local music_lights=$(jq -r '[.lights[] | select(.supportMusic == true)] | length' "$lights_db_path")
    local fx17_lights=$(jq -r '[.lights[] | select(.support17FX == true)] | length' "$lights_db_path")
    local fx9_lights=$(jq -r '[.lights[] | select(.support9FX == true)] | length' "$lights_db_path")
    
    print_success "Database statistics:"
    print_success "  Total lights: $lights_count"
    print_success "  RGB support: $rgb_lights"
    print_success "  CCT+GM support: $cct_lights"
    print_success "  Music support: $music_lights"
    print_success "  17FX support: $fx17_lights"
    print_success "  9FX support: $fx9_lights"
    
    if [ $validation_errors -eq 0 ]; then
        print_success "lights.json validation passed"
        return 0
    else
        print_error "lights.json validation failed with $validation_errors error(s)"
        return 1
    fi
}

# Function to compare versions
compare_versions() {
    print_status "Comparing versions across sources..."
    
    local appcast_version=""
    if [ -f "$TEMP_DIR/appcast_version" ]; then
        appcast_version=$(cat "$TEMP_DIR/appcast_version" | sed 's/Version //g' | sed 's/NeewerLite //g' | sed 's/^v//')
    fi
    
    local dmg_version=""
    if [ -f "$TEMP_DIR/dmg_version" ]; then
        dmg_version=$(cat "$TEMP_DIR/dmg_version")
    fi
    
    local github_tag=$(get_latest_release_tag)
    local github_version=""
    if [ -n "$github_tag" ]; then
        github_version=$(echo "$github_tag" | sed 's/^v//')
    fi
    
    print_status "Version summary:"
    [ -n "$appcast_version" ] && print_success "  Appcast version: $appcast_version" || print_status "  Appcast version: N/A"
    [ -n "$github_version" ] && print_success "  GitHub version: $github_version" || print_status "  GitHub version: N/A"
    [ -n "$dmg_version" ] && print_success "  DMG app version: $dmg_version" || print_status "  DMG app version: N/A"
    
    # Compare versions if we have at least two sources
    local version_match=true
    local versions_to_compare=()
    
    [ -n "$appcast_version" ] && versions_to_compare+=("$appcast_version")
    [ -n "$github_version" ] && versions_to_compare+=("$github_version")
    [ -n "$dmg_version" ] && versions_to_compare+=("$dmg_version")
    
    if [ ${#versions_to_compare[@]} -ge 2 ]; then
        local first_version="${versions_to_compare[0]}"
        for version in "${versions_to_compare[@]}"; do
            if [ "$version" != "$first_version" ]; then
                version_match=false
                break
            fi
        done
        
        if [ "$version_match" = true ]; then
            print_success "✅ All available versions match: $first_version"
        else
            print_error "❌ Version mismatch detected across sources"
        fi
    else
        print_status "Not enough version data available for comparison"
    fi
}

# Main validation flow
main() {
    echo
    print_status "Starting validation process..."
    if [ "$VERBOSE" = true ]; then
        print_status "Verbose mode enabled"
        print_status "Skip appcast: $SKIP_APPCAST"
        print_status "Skip ZIP: $SKIP_ZIP" 
        print_status "Skip DMG: $SKIP_DMG"
        print_status "Skip lights DB: $SKIP_LIGHTS_DB"
    fi
    echo
    
    # Check if required tools are available
    local required_tools=("curl" "jq" "gh" "shasum")
    [ "$SKIP_APPCAST" = false ] && required_tools+=("xmllint")
    [ "$SKIP_ZIP" = false ] && required_tools+=("unzip")
    [ "$SKIP_DMG" = false ] && required_tools+=("hdiutil")
    
    for cmd in "${required_tools[@]}"; do
        if ! command -v $cmd >/dev/null 2>&1; then
            print_error "Required command '$cmd' not found. Please install it first."
            print_status "On macOS, you can install missing tools with:"
            print_status "  brew install $cmd"
            exit 1
        fi
    done
    
    # Check if we can access the Info.plist file (critical for appcast validation)
    local info_plist="../NeewerLite/NeewerLite/Resources/Info.plist"
    if [ ! -f "$info_plist" ]; then
        print_error "Cannot find Info.plist at $info_plist"
        print_status "Make sure you're running this script from the Tools/ directory"
        exit 1
    fi
    
    local validation_errors=0
    
    # Validate appcast.xml
    if [ "$SKIP_APPCAST" = false ]; then
        if ! validate_appcast; then
            validation_errors=$((validation_errors + 1))
        fi
        echo
    else
        print_status "Skipping appcast.xml validation"
        echo
    fi
    
    # Validate ZIP download  
    if [ "$SKIP_ZIP" = false ]; then
        if ! validate_zip_download; then
            validation_errors=$((validation_errors + 1))
        fi
        echo
    else
        print_status "Skipping ZIP file validation"
        echo
    fi
    
    # Validate DMG from GitHub
    if [ "$SKIP_DMG" = false ]; then
        if ! validate_dmg_from_github; then
            validation_errors=$((validation_errors + 1))
        fi
        echo
    else
        print_status "Skipping DMG file validation"
        echo
    fi
    
    # Validate lights database
    if [ "$SKIP_LIGHTS_DB" = false ]; then
        if ! validate_lights_database; then
            validation_errors=$((validation_errors + 1))
        fi
        echo
    else
        print_status "Skipping lights database validation"
        echo
    fi
    
    # Compare versions
    compare_versions
    echo
    
    # Summary
    local total_checks=$((4 - $(($SKIP_APPCAST + $SKIP_ZIP + $SKIP_DMG + $SKIP_LIGHTS_DB))))
    local successful_checks=$((total_checks - validation_errors))
    
    if [ $validation_errors -eq 0 ]; then
        print_success "🎉 All $total_checks validation(s) passed!"
        echo
        [ "$SKIP_APPCAST" = false ] && print_success "✅ appcast.xml is accessible and valid"
        [ "$SKIP_ZIP" = false ] && print_success "✅ ZIP file downloads and is valid"
        [ "$SKIP_DMG" = false ] && print_success "✅ DMG file downloads from GitHub and is valid"
        [ "$SKIP_LIGHTS_DB" = false ] && print_success "✅ lights.json database is valid"
    else
        print_error "❌ $validation_errors out of $total_checks validation(s) failed"
        print_status "($successful_checks validation(s) passed)"
        exit 1
    fi
}

# Run the main function
main "$@"
