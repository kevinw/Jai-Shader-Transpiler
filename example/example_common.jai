READBACK_SAMPLE_POINTS :: Vector2.[
    .{ 0.5, 0.5 },
    .{ 0.25, 0.25 },
    .{ 0.75, 0.25 },
    .{ 0.25, 0.75 },
    .{ 0.75, 0.75 },
];

validate_readback_samples :: (backend: string, pixels: []u8, width: s32, height: s32, bytes_per_row: s64, is_bgra := false) -> bool {
    sample_count := READBACK_SAMPLE_POINTS.count;
    non_black := 0;
    min_luma: float32 = 999.0;
    max_luma: float32 = -1.0;
    sum_luma: float32 = 0;

    for READBACK_SAMPLE_POINTS {
        px := clamp(cast(s32) floor(it.x * xx width), 0, width - 1);
        py := clamp(cast(s32) floor(it.y * xx height), 0, height - 1);
        offset := cast(s64) py * bytes_per_row + cast(s64) px * 4;
        p := pixels.data + offset;

        r, g, b: float32;
        if is_bgra {
            b = xx p[0] / 255.0;
            g = xx p[1] / 255.0;
            r = xx p[2] / 255.0;
        } else {
            r = xx p[0] / 255.0;
            g = xx p[1] / 255.0;
            b = xx p[2] / 255.0;
        }

        luma := cast(float32) (0.2126 * r + 0.7152 * g + 0.0722 * b);

        if luma > 0.02 non_black += 1;
        min_luma = min(min_luma, luma);
        max_luma = max(max_luma, luma);
        sum_luma += luma;
    }

    avg_luma := sum_luma / xx sample_count;
    log("READBACK_SUMMARY backend=% samples=% non_black=% avg_luma=% min_luma=% max_luma=%",
        backend, sample_count, non_black, avg_luma, min_luma, max_luma);

    ok := (non_black >= 2) && (max_luma > 0.05) && ((max_luma - min_luma) > 0.02);
    if !ok log_error("READBACK_FAIL backend=%", backend);
    return ok;
}
