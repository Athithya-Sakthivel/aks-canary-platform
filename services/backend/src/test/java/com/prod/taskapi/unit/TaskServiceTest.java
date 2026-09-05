package com.prod.taskapi.unit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import com.prod.taskapi.dto.TaskRequest;
import com.prod.taskapi.dto.TaskResponse;
import com.prod.taskapi.entity.Status;
import com.prod.taskapi.entity.Task;
import com.prod.taskapi.repository.TaskRepository;
import com.prod.taskapi.service.TaskService;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Timer;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class TaskServiceTest {

  @Mock private TaskRepository taskRepository;

  @Mock private Counter taskCreatedCounter;

  @Mock private Timer taskCreationTimer;

  @Mock private Timer taskFetchTimer;

  private TaskService taskService;

  private Task task;
  private TaskRequest taskRequest;

  @BeforeEach
  void setUp() throws Exception {
    // Timer.record(Supplier) returns the supplied object when called.
    // Mockito cannot directly mock generic Supplier easily, so use real
    // SimpleMeterRegistry-based timers OR stub with thenAnswer.
    // Approach: use minimal real Timers backed by SimpleMeterRegistry.

    io.micrometer.core.instrument.simple.SimpleMeterRegistry registry =
        new io.micrometer.core.instrument.simple.SimpleMeterRegistry();

    taskCreatedCounter = registry.counter("task_created_total");
    taskCreationTimer = registry.timer("task_creation_duration");
    taskFetchTimer = registry.timer("task_fetch_duration");

    taskService =
        new TaskService(taskRepository, taskCreatedCounter, taskCreationTimer, taskFetchTimer);

    task = new Task("Test Task", "Description", Status.PENDING, 1L);
    task.setId(1L);
    taskRequest = new TaskRequest("Test Task", "Description", Status.PENDING);
  }

  @Test
  void createTaskShouldSucceed() {
    when(taskRepository.save(any(Task.class))).thenReturn(task);

    TaskResponse response = taskService.createTask(taskRequest, 1L);

    assertThat(response.title()).isEqualTo("Test Task");
    verify(taskRepository).save(any(Task.class));
  }

  @Test
  void getTasksShouldReturnList() {
    when(taskRepository.findByUserId(1L)).thenReturn(List.of(task));

    List<TaskResponse> tasks = taskService.getTasks(1L);

    assertThat(tasks).hasSize(1);
    assertThat(tasks.get(0).id()).isEqualTo(1L);
  }

  @Test
  void getTaskShouldReturnTask() {
    when(taskRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(task));

    TaskResponse response = taskService.getTask(1L, 1L);

    assertThat(response.id()).isEqualTo(1L);
  }

  @Test
  void getTaskNotFoundShouldThrow() {
    when(taskRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> taskService.getTask(1L, 1L))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessage("Task not found");
  }

  @Test
  void updateTaskShouldSucceed() {
    when(taskRepository.findByIdAndUserId(1L, 1L)).thenReturn(Optional.of(task));
    when(taskRepository.save(any(Task.class))).thenReturn(task);

    TaskResponse response = taskService.updateTask(1L, taskRequest, 1L);

    assertThat(response.title()).isEqualTo("Test Task");
  }

  @Test
  void deleteTaskShouldSucceed() {
    doNothing().when(taskRepository).deleteByIdAndUserId(1L, 1L);

    taskService.deleteTask(1L, 1L);

    verify(taskRepository).deleteByIdAndUserId(1L, 1L);
  }
}
