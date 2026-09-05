package com.prod.taskapi.service;

import com.prod.taskapi.dto.TaskRequest;
import com.prod.taskapi.dto.TaskResponse;
import com.prod.taskapi.entity.Status;
import com.prod.taskapi.entity.Task;
import com.prod.taskapi.repository.TaskRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Timer;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TaskService {

  private static final Logger log = LoggerFactory.getLogger(TaskService.class);

  private final TaskRepository taskRepository;
  private final Counter taskCreatedCounter;
  private final Timer taskCreationTimer;
  private final Timer taskFetchTimer;

  public TaskService(
      TaskRepository taskRepository,
      Counter taskCreatedCounter,
      Timer taskCreationTimer,
      Timer taskFetchTimer) {
    this.taskRepository = taskRepository;
    this.taskCreatedCounter = taskCreatedCounter;
    this.taskCreationTimer = taskCreationTimer;
    this.taskFetchTimer = taskFetchTimer;
  }

  @Transactional
  public TaskResponse createTask(TaskRequest request, Long userId) {
    log.info("Creating task for authenticated user");

    Status status = request.status() != null ? request.status() : Status.PENDING;

    Task task = new Task(request.title(), request.description(), status, userId);

    /*
     * Use Timer.record(Supplier) rather than recordCallable().
     * recordCallable() declares throws Exception, which is unnecessary for
     * Spring Data repository operations and would otherwise require checked
     * exception handling in this method.
     */
    Task saved = taskCreationTimer.record(() -> taskRepository.save(task));

    taskCreatedCounter.increment();

    log.info("Task created successfully");
    return toResponse(saved);
  }

  @Transactional(readOnly = true)
  public List<TaskResponse> getTasks(Long userId) {
    log.info("Fetching tasks for authenticated user");

    List<Task> tasks = taskFetchTimer.record(() -> taskRepository.findByUserId(userId));

    return tasks.stream().map(this::toResponse).toList();
  }

  @Transactional(readOnly = true)
  public TaskResponse getTask(Long taskId, Long userId) {
    log.info("Fetching task");

    Task task =
        taskRepository
            .findByIdAndUserId(taskId, userId)
            .orElseThrow(
                () -> {
                  log.warn("Task not found");
                  return new IllegalArgumentException("Task not found");
                });

    return toResponse(task);
  }

  @Transactional
  public TaskResponse updateTask(Long taskId, TaskRequest request, Long userId) {
    log.info("Updating task");

    Task task =
        taskRepository
            .findByIdAndUserId(taskId, userId)
            .orElseThrow(
                () -> {
                  log.warn("Task not found for update");
                  return new IllegalArgumentException("Task not found");
                });

    if (request.title() != null) {
      task.setTitle(request.title());
    }

    if (request.description() != null) {
      task.setDescription(request.description());
    }

    if (request.status() != null) {
      task.setStatus(request.status());
    }

    Task updated = taskRepository.save(task);

    log.info("Task updated successfully");
    return toResponse(updated);
  }

  @Transactional
  public void deleteTask(Long taskId, Long userId) {
    log.info("Deleting task");

    taskRepository.deleteByIdAndUserId(taskId, userId);

    log.info("Task delete operation completed");
  }

  private TaskResponse toResponse(Task task) {
    return new TaskResponse(
        task.getId(),
        task.getTitle(),
        task.getDescription(),
        task.getStatus(),
        task.getUserId(),
        task.getCreatedAt(),
        task.getUpdatedAt());
  }
}
