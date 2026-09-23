// Ordered dithering for soft-looking effects that must stay in the opaque
// pass (the glass refraction only sees opaque things): discard the fragment
// when coverage is below this pixel's Bayer threshold.
bool dither_discard(float coverage, vec2 frag_coord) {
	ivec2 px = ivec2(frag_coord) % 4;
	int idx = px.x + px.y * 4;
	float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return coverage <= (bayer[idx] + 0.5) / 16.0;
}
