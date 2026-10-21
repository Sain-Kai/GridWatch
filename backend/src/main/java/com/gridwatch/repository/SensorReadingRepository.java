package com.gridwatch.repository;

import com.gridwatch.model.SensorReading;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface SensorReadingRepository extends JpaRepository<SensorReading, Long> {
    List<SensorReading> findTop20ByNodeIdOrderByCreatedAtDesc(Integer nodeId);
    Optional<SensorReading> findTopByNodeIdOrderByCreatedAtDesc(Integer nodeId);
    Optional<SensorReading> findTopByNodeIdAndClassificationNotOrderByCreatedAtDesc(Integer nodeId, String classification);
    Optional<SensorReading> findFirstByNodeIdAndSequenceId(Integer nodeId, Long sequenceId);
    // Latest reading that came in over a live link (not a buffered replay)
    Optional<SensorReading> findTopByNodeIdAndBufferedFalseOrderByCreatedAtDesc(Integer nodeId);
    // Most-recent 20 for history / sparkline (includes buffered, for full picture)
    List<SensorReading> findTop20ByNodeIdOrderByCreatedAtAsc(Integer nodeId);
}
