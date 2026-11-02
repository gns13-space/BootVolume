// 정적 파일은 그대로 내보내고, 영상(.mp4)만 Range 요청에 206 으로 응답한다(Safari 재생용).
export default {
  async fetch(request, env) {
    const res = await env.ASSETS.fetch(request);
    const url = new URL(request.url);
    if (!url.pathname.endsWith('.mp4') || res.status !== 200) return res;
    const range = request.headers.get('Range');
    const headers = new Headers(res.headers);
    headers.set('Accept-Ranges', 'bytes');
    if (!range) return new Response(res.body, { status: 200, headers });
    const buf = await res.arrayBuffer();
    const size = buf.byteLength;
    const m = /^bytes=(\d*)-(\d*)$/.exec(range.trim());
    if (!m || (m[1] === '' && m[2] === '')) return new Response(buf, { status: 200, headers });
    let start, end;
    if (m[1] === '') { start = Math.max(0, size - Number(m[2])); end = size - 1; }
    else { start = Number(m[1]); end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1); }
    if (start >= size || start > end) {
      headers.set('Content-Range', `bytes */${size}`);
      return new Response(null, { status: 416, headers });
    }
    headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
    headers.set('Content-Length', String(end - start + 1));
    return new Response(buf.slice(start, end + 1), { status: 206, headers });
  },
};
