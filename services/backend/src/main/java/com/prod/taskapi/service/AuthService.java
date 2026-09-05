package com.prod.taskapi.service;

import com.prod.taskapi.dto.JwtResponse;
import com.prod.taskapi.dto.LoginRequest;
import com.prod.taskapi.dto.RegisterRequest;
import com.prod.taskapi.entity.Role;
import com.prod.taskapi.entity.User;
import com.prod.taskapi.repository.UserRepository;
import com.prod.taskapi.security.JwtService;
import io.micrometer.core.instrument.Counter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

  private static final Logger log = LoggerFactory.getLogger(AuthService.class);

  private final UserRepository userRepository;
  private final PasswordEncoder passwordEncoder;
  private final JwtService jwtService;
  private final Counter authSuccessCounter;
  private final Counter authFailureCounter;

  public AuthService(
      UserRepository userRepository,
      PasswordEncoder passwordEncoder,
      JwtService jwtService,
      Counter authSuccessCounter,
      Counter authFailureCounter) {
    this.userRepository = userRepository;
    this.passwordEncoder = passwordEncoder;
    this.jwtService = jwtService;
    this.authSuccessCounter = authSuccessCounter;
    this.authFailureCounter = authFailureCounter;
  }

  @Transactional
  public JwtResponse register(RegisterRequest request) {
    log.info("Registration attempt");

    if (userRepository.existsByUsername(request.username())) {
      log.warn("Registration failed: username already exists");
      authFailureCounter.increment();
      throw new IllegalArgumentException("Username already taken");
    }

    if (userRepository.existsByEmail(request.email())) {
      log.warn("Registration failed: email already exists");
      authFailureCounter.increment();
      throw new IllegalArgumentException("Email already registered");
    }

    User user =
        new User(
            request.username(),
            request.email(),
            passwordEncoder.encode(request.password()),
            Role.USER);

    userRepository.save(user);

    String token =
        jwtService.generateToken(
            user.getId(),
            user.getUsername(),
            user.getRole().name());

    authSuccessCounter.increment();
    log.info("Registration successful");

    return new JwtResponse(
        token,
        user.getUsername(),
        user.getRole().name());
  }

  @Transactional(readOnly = true)
  public JwtResponse login(LoginRequest request) {
    log.info("Login attempt");

    User user =
        userRepository
            .findByUsername(request.username())
            .orElseThrow(
                () -> {
                  authFailureCounter.increment();
                  log.warn("Login failed: invalid credentials");
                  return new BadCredentialsException("Invalid username or password");
                });

    if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
      authFailureCounter.increment();
      log.warn("Login failed: invalid credentials");
      throw new BadCredentialsException("Invalid username or password");
    }

    String token =
        jwtService.generateToken(
            user.getId(),
            user.getUsername(),
            user.getRole().name());

    authSuccessCounter.increment();
    log.info("Login successful");

    return new JwtResponse(
        token,
        user.getUsername(),
        user.getRole().name());
  }
}