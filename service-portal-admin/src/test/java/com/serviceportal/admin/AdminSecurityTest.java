/*
 * MIT License
 *
 * Copyright (c) 2026 Luiz
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
package com.serviceportal.admin;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.micrometer.metrics.test.autoconfigure.AutoConfigureMetrics;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

/** Pins the security rules of the admin server (public routes, CSRF, registration). */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureMetrics
class AdminSecurityTest {

    private static final String REGISTRATION =
            """
            {"name":"test-client","healthUrl":"http://localhost:9999/actuator/health",\
            "managementUrl":"http://localhost:9999/actuator","serviceUrl":"http://localhost:9999/"}
            """;

    @Autowired private MockMvc mvc;

    @Test
    @DisplayName("anonymous GET /actuator/health is public")
    void healthIsPublic() throws Exception {
        mvc.perform(get("/actuator/health")).andExpect(status().isOk());
    }

    @Test
    @DisplayName(
            "anonymous GET /actuator/prometheus is public (Prometheus scrapes without credentials)")
    void prometheusIsPublic() throws Exception {
        mvc.perform(get("/actuator/prometheus")).andExpect(status().isOk());
    }

    @Test
    @DisplayName("anonymous GET /actuator/info is public")
    void infoIsPublic() throws Exception {
        mvc.perform(get("/actuator/info")).andExpect(status().isOk());
    }

    @Test
    @DisplayName("anonymous browser GET / redirects to the login page")
    void rootRedirectsToLogin() throws Exception {
        mvc.perform(get("/").accept(MediaType.TEXT_HTML))
                .andExpect(status().isFound())
                // Spring Security 7 devolve o Location relativo (/login); 6.x devolvia absoluto.
                .andExpect(header().string("Location", org.hamcrest.Matchers.endsWith("/login")));
    }

    @Test
    @DisplayName("anonymous GET /login is public")
    void loginIsPublic() throws Exception {
        mvc.perform(get("/login")).andExpect(status().isOk());
    }

    @Test
    @DisplayName("POST /instances without credentials is 401")
    void registrationWithoutCredentials() throws Exception {
        mvc.perform(
                        post("/instances")
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(REGISTRATION))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName(
            "POST /instances with basic auth registers a client (CSRF does not block; SBA answers 200)")
    void registrationWithBasicAuth() throws Exception {
        mvc.perform(
                        post("/instances")
                                .with(httpBasic("admin", "admin"))
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(REGISTRATION))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("POST /instances with wrong password is 401")
    void registrationWithWrongPassword() throws Exception {
        mvc.perform(
                        post("/instances")
                                .with(httpBasic("admin", "wrong"))
                                .contentType(MediaType.APPLICATION_JSON)
                                .content(REGISTRATION))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("actuator/env is not exposed to anonymous users")
    void envNotServed() throws Exception {
        int s = mvc.perform(get("/actuator/env")).andReturn().getResponse().getStatus();
        org.assertj.core.api.Assertions.assertThat(s).isIn(302, 401, 404);
    }

    @Test
    @DisplayName("actuator/env is not exposed even to the authenticated admin")
    void envNotServedToAdmin() throws Exception {
        mvc.perform(get("/actuator/env").with(httpBasic("admin", "admin")))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("successful login honours the redirectTo parameter")
    void loginRedirectsToRedirectTo() throws Exception {
        mvc.perform(
                        post("/login")
                                .param("username", "admin")
                                .param("password", "admin")
                                .param("redirectTo", "/applications")
                                .with(
                                        org.springframework.security.test.web.servlet.request
                                                .SecurityMockMvcRequestPostProcessors.csrf()))
                .andExpect(status().isFound())
                .andExpect(header().string("Location", "/applications"));
    }

    @Test
    @DisplayName("successful login without redirectTo goes to the root")
    void loginDefaultsToRoot() throws Exception {
        mvc.perform(
                        post("/login")
                                .param("username", "admin")
                                .param("password", "admin")
                                .with(
                                        org.springframework.security.test.web.servlet.request
                                                .SecurityMockMvcRequestPostProcessors.csrf()))
                .andExpect(status().isFound())
                .andExpect(header().string("Location", "/"));
    }

    @Test
    @DisplayName("health hides component details from anonymous users")
    void healthHidesDetailsFromAnonymous() throws Exception {
        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(
                        org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath(
                                        "$.components")
                                .doesNotExist());
    }

    @Test
    @DisplayName("DELETE /instances/{id} with basic auth is not blocked by CSRF")
    void deregistrationWithBasicAuth() throws Exception {
        int s =
                mvc.perform(delete("/instances/unknown").with(httpBasic("admin", "admin")))
                        .andReturn()
                        .getResponse()
                        .getStatus();
        org.assertj.core.api.Assertions.assertThat(s).isNotEqualTo(403);
    }

    @Test
    @DisplayName("POST /logout without CSRF token is rejected")
    void logoutRequiresCsrf() throws Exception {
        mvc.perform(post("/logout").with(httpBasic("admin", "admin")))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("POST to actuator without CSRF token is rejected")
    void actuatorPostRequiresCsrf() throws Exception {
        mvc.perform(post("/actuator/health").with(httpBasic("admin", "admin")))
                .andExpect(status().isForbidden());
    }
}
