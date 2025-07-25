# NeewerLite Release Validation Script

The `validate.sh` script helps you validate a published NeewerLite release by checking:

1. **Appcast.xml validation** - Downloads and validates the appcast.xml from the remote server
2. **ZIP file validation** - Downloads and validates the ZIP file from the website  
3. **DMG file validation** - Downloads and validates the DMG file from the GitHub release

## Usage

```bash
# Run all validations
./validate.sh

# Run with options
./validate.sh --help                # Show help
./validate.sh --skip-zip            # Skip ZIP validation
./validate.sh --skip-appcast        # Skip appcast validation  
./validate.sh --skip-dmg            # Skip DMG validation
./validate.sh -v                    # Verbose mode
```

## What it validates

### Appcast.xml
- ✅ Downloads appcast.xml from the URL specified in Info.plist (`SUFeedURL`)
- ✅ Validates XML structure
- ✅ Extracts version and download URL using Sparkle format
- ✅ Supports both title-based and `sparkle:shortVersionString` version extraction

### ZIP File
- ✅ Downloads ZIP file from the URL found in appcast.xml
- ✅ Validates ZIP file integrity
- ✅ Shows file size and SHA256 checksum
- ✅ Lists ZIP contents

### DMG File  
- ✅ Gets latest GitHub release via GitHub API
- ✅ Downloads DMG file from GitHub release assets
- ✅ Validates DMG file format (multiple detection methods)
- ✅ Attempts to mount DMG and verify NeewerLite.app contents
- ✅ Extracts app version from mounted DMG
- ✅ Shows file size and SHA256 checksum

### Version Comparison
- ✅ Compares versions across all sources (appcast, GitHub, DMG app)
- ✅ Reports version mismatches
- ✅ Shows summary of all found versions

## Requirements

The script requires these command-line tools:
- `curl` - for downloading files
- `xmllint` - for XML parsing (appcast validation)
- `unzip` - for ZIP validation
- `jq` - for JSON parsing (GitHub API)
- `gh` - GitHub CLI (GitHub API access)
- `shasum` - for checksums
- `hdiutil` - for DMG validation (macOS only)

## Configuration

The script automatically reads the appcast URL from:
```
../NeewerLite/NeewerLite/Resources/Info.plist
```

Make sure to run the script from the `Tools/` directory.

## Examples

```bash
# Validate everything
./validate.sh

# Only validate GitHub DMG
./validate.sh --skip-appcast --skip-zip

# Verbose mode with only appcast validation  
./validate.sh -v --skip-zip --skip-dmg
```

## Integration with Publish Script

The `publish.sh` script now includes a tip to run validation after publishing:

```bash
./publish.sh
# ... publishing happens ...
# ✅ Release v1.6.6 published to GitHub and website.
# 
# 💡 Tip: You can validate the published release using:
#    ./validate.sh
```
