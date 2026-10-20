/*
 * Stand-alone check of the ATI Radeon emulation's host GL back end
 * (hw/display/ati_gl.c) and of the renderer's own shaders (ati_glr.c),
 * without QEMU: open the host GL on a separate thread exactly as the
 * "ati-gl" thread does, compile and link the R100 pixel-pipeline program,
 * draw into a framebuffer object with a depth/stencil buffer and read the
 * pixels back.
 *
 * Built and run by ati/tests/run-gl-smoke.sh against a prepared QEMU tree.
 *
 * Copyright (c) 2026 ClassicMac contributors
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ati_gl.h"
#include "ati_gl_smoke_shaders.h"   /* vs_src, fs_src extracted from ati_glr.c */

#define W 64
#define H 64

static int failures;

static void check(int ok, const char *what)
{
    printf("%s  %s\n", ok ? "  OK" : "FAIL", what);
    if (!ok) {
        failures++;
    }
}

static GLuint shader(ATIGL *gl, GLenum type, const char *src)
{
    const GLchar *srcs[2] = { ATI_GLSL_VERSION, src };
    GLuint s = gl->CreateShader(type);
    GLint ok = 0;

    gl->ShaderSource(s, 2, srcs, NULL);
    gl->CompileShader(s);
    gl->GetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[2048] = "";
        gl->GetShaderInfoLog(s, sizeof(log), NULL, log);
        printf("shader log: %s\n", log);
    }
    check(ok, type == GL_VERTEX_SHADER ? "vertex shader compiles"
                                       : "fragment shader compiles");
    return s;
}

static void *run(void *arg)
{
    ATIGL gl;
    char info[256] = "";
    static const char *attrs[] = { "a_pos", "a_c0", "a_c1", "a_t0", "a_t1", "a_t2" };
    GLuint prog, vao, vbo, tex, fbo, rb;
    GLint ok = 0;
    float v[3][24];
    uint8_t px[W * H * 4];

    (void)arg;
    if (!ati_gl_open(&gl, info, sizeof(info))) {
        printf("FAIL  host GL: %s\n", info);
        failures++;
        return NULL;
    }
    printf("host GL: %s\n", info);
    check(strstr(info, "GL 4.") != NULL || strstr(info, "OpenGL ES") != NULL,
          "OpenGL 4 Core (or ES 3) context");

    prog = gl.CreateProgram();
    gl.AttachShader(prog, shader(&gl, GL_VERTEX_SHADER, vs_src));
    gl.AttachShader(prog, shader(&gl, GL_FRAGMENT_SHADER, fs_src));
    for (int i = 0; i < 6; i++) {
        gl.BindAttribLocation(prog, i, attrs[i]);
    }
    gl.LinkProgram(prog);
    gl.GetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[2048] = "";
        gl.GetProgramInfoLog(prog, sizeof(log), NULL, log);
        printf("link log: %s\n", log);
    }
    check(ok, "R100 pixel-pipeline program links");
    gl.UseProgram(prog);

    /* render target as ati_glr.c makes it: RGBA8 texture + D24S8 */
    gl.GenTextures(1, &tex);
    gl.BindTexture(GL_TEXTURE_2D, tex);
    gl.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, W, H, 0, GL_RGBA,
                  GL_UNSIGNED_BYTE, NULL);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    gl.GenFramebuffers(1, &fbo);
    gl.BindFramebuffer(GL_FRAMEBUFFER, fbo);
    gl.FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                            GL_TEXTURE_2D, tex, 0);
    gl.GenRenderbuffers(1, &rb);
    gl.BindRenderbuffer(GL_RENDERBUFFER, rb);
    gl.RenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, W, H);
    gl.FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
                               GL_RENDERBUFFER, rb);
    check(gl.CheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
          "framebuffer object complete");

    gl.Viewport(0, 0, W, H);
    gl.ClearColor(0, 0, 1, 1);
    gl.ClearDepthf(1.0f);
    gl.ClearStencil(0);
    gl.Clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

    /* one red, Gouraud, untextured triangle covering the lower-left half */
    memset(v, 0, sizeof(v));
    float pos[3][2] = { { 0, 0 }, { W, 0 }, { 0, H } };
    for (int i = 0; i < 3; i++) {
        v[i][0] = pos[i][0];
        v[i][1] = pos[i][1];
        v[i][2] = 0.5f;          /* z */
        v[i][3] = 1.0f;          /* rhw */
        v[i][4] = 1.0f;          /* c0 = red */
        v[i][7] = 1.0f;
    }
    gl.Uniform2f(gl.GetUniformLocation(prog, "fbsize"), W, H);
    gl.Uniform1i(gl.GetUniformLocation(prog, "stage_en"), 0);
    gl.Uniform1i(gl.GetUniformLocation(prog, "tex_en"), 0);
    gl.Enable(GL_DEPTH_TEST);
    gl.DepthFunc(GL_LESS);
    gl.GenVertexArrays(1, &vao);
    gl.BindVertexArray(vao);
    gl.GenBuffers(1, &vbo);
    gl.BindBuffer(GL_ARRAY_BUFFER, vbo);
    gl.BufferData(GL_ARRAY_BUFFER, sizeof(v), v, GL_STREAM_DRAW);
    for (int i = 0; i < 6; i++) {
        gl.VertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, 24 * sizeof(float),
                               (const void *)(uintptr_t)(i * 4 * sizeof(float)));
        gl.EnableVertexAttribArray(i);
    }
    gl.DrawArrays(GL_TRIANGLES, 0, 3);
    gl.PixelStorei(GL_PACK_ALIGNMENT, 1);
    gl.ReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
    gl.Finish();

    const uint8_t *in = px + (8 * W + 8) * 4;       /* inside the triangle */
    const uint8_t *out = px + (60 * W + 60) * 4;    /* outside it */
    printf("pixel (8,8) = %u,%u,%u,%u; pixel (60,60) = %u,%u,%u,%u\n",
           in[0], in[1], in[2], in[3], out[0], out[1], out[2], out[3]);
    check(in[0] == 255 && in[1] == 0 && in[2] == 0 && in[3] == 255,
          "triangle drawn with the vertex colour");
    check(out[0] == 0 && out[1] == 0 && out[2] == 255,
          "outside the triangle keeps the clear colour");
    check(gl.GetError() == GL_NO_ERROR, "no GL error");
    ati_gl_close();
    return NULL;
}

int main(void)
{
    pthread_t t;

    /* not the main thread, as in QEMU */
    pthread_create(&t, NULL, run, NULL);
    pthread_join(t, NULL);
    printf("%s\n", failures ? "ATI GL smoke test FAILED" : "ATI GL smoke test passed");
    return failures ? 1 : 0;
}
