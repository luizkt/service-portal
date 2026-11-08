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
package com.serviceportal.admin.config;

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Detects the well-known default admin credentials at startup. Logs a WARN naming the settings
 * (never their values) and fails the startup when profile {@code prod} is active or {@code
 * sba.security.strict=true}.
 */
@Component
public class SecurityDefaultsGuard {

    private static final Logger log = LoggerFactory.getLogger(SecurityDefaultsGuard.class);
    private static final String DEFAULT_CREDENTIAL = "admin";

    private final Environment env;

    public SecurityDefaultsGuard(Environment env) {
        this.env = env;
    }

    @PostConstruct
    void check() {
        if (!DEFAULT_CREDENTIAL.equals(env.getProperty("spring.security.user.name"))
                || !DEFAULT_CREDENTIAL.equals(env.getProperty("spring.security.user.password"))) {
            return;
        }
        boolean strict =
                env.acceptsProfiles(Profiles.of("prod"))
                        || env.getProperty("sba.security.strict", Boolean.class, false);
        String message =
                "Insecure default settings in use: SBA_USERNAME/SBA_PASSWORD"
                        + " (spring.security.user.*)";
        if (strict) {
            throw new IllegalStateException(message + ". Refusing to start (prod/strict mode).");
        }
        log.warn("{}. Change them before deploying (prod/strict mode refuses to start).", message);
    }
}
