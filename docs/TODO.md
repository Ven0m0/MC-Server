# TODO

## ✓ [Chunk cleaner](https://github.com/zeroBzeroT/ChunkCleaner)

**Status**: Implemented in `tools/world-optimize.sh`

The chunk cleaner has been implemented with additional world optimization features:

- Automatic ChunkCleaner download and installation
- Chunk cleaning based on inhabited ticks (configurable)
- Old player data cleanup
- Statistics and advancement cleanup
- Session lock removal
- Region file optimization
- Comprehensive world statistics
- Dry-run mode for safe testing
- Automatic backups before operations

**Usage**:

```bash
# Clean chunks with default settings (200 inhabited ticks)
./tools/world-optimize.sh chunks

# Clean chunks with custom threshold
./tools/world-optimize.sh chunks --min-ticks 500

# Run all optimizations
./tools/world-optimize.sh all

# Dry run to see what would be changed
./tools/world-optimize.sh all --dry-run

# Show world statistics
./tools/world-optimize.sh info
```
