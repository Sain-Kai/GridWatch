package com.gridwatch.model;

import com.fasterxml.jackson.annotation.JsonAlias;
import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "sensor_reading")
public class SensorReading {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Integer nodeId;
    private Long sequenceId;
    private Double tempC;
    private Double tempRiseRate;
    private Double ambientC;
    private Integer loadPercent; // null when no electrical load sensor is installed
    private Integer ir1;
    private Integer ir2;
    @JsonAlias({"fsr"})
    private Integer fsrValue;
    @JsonAlias({"fanVerifiedSpinning"})
    private Boolean fanVerified;
    private Boolean fanDriverEnabled = false;
    private Boolean ambientSensorOk = true;
    private String classification; // NORMAL / THERMAL_WARNING / COOLING_FAILURE / CRITICAL_OVERHEAT / TAMPER / POSSIBLE_TAMPER / SENSOR_FAULT
    private Integer healthScore;   // 0-100 composite score

    private Boolean buffered = false;      // true if this reading was replayed from a node's outage buffer
    private Long bufferedAgoMs;            // how long ago it was actually captured, if buffered

    @Column(length = 4000)
    private String incidentReport; // filled in by RagService when classification != NORMAL
    private String reportProvider; // "nvidia-cloud" or "ollama-local" - which backend actually generated it

    private Instant createdAt = Instant.now();

    public Long getId() { return id; }
    public Integer getNodeId() { return nodeId; }
    public Long getSequenceId() { return sequenceId; }
    public void setSequenceId(Long sequenceId) { this.sequenceId = sequenceId; }
    public void setNodeId(Integer nodeId) { this.nodeId = nodeId; }
    public Double getTempC() { return tempC; }
    public void setTempC(Double tempC) { this.tempC = tempC; }
    public Double getTempRiseRate() { return tempRiseRate; }
    public void setTempRiseRate(Double tempRiseRate) { this.tempRiseRate = tempRiseRate; }
    public Double getAmbientC() { return ambientC; }
    public void setAmbientC(Double ambientC) { this.ambientC = ambientC; }
    public Integer getLoadPercent() { return loadPercent; }
    public void setLoadPercent(Integer loadPercent) { this.loadPercent = loadPercent; }
    public Integer getIr1() { return ir1; }
    public void setIr1(Integer ir1) { this.ir1 = ir1; }
    public Integer getIr2() { return ir2; }
    public void setIr2(Integer ir2) { this.ir2 = ir2; }
    public Integer getFsrValue() { return fsrValue; }
    public void setFsrValue(Integer fsrValue) { this.fsrValue = fsrValue; }
    public Boolean getFanVerified() { return fanVerified; }
    public Boolean getFanDriverEnabled() { return fanDriverEnabled; }
    public void setFanDriverEnabled(Boolean fanDriverEnabled) { this.fanDriverEnabled = fanDriverEnabled; }
    public Boolean getAmbientSensorOk() { return ambientSensorOk; }
    public void setAmbientSensorOk(Boolean ambientSensorOk) { this.ambientSensorOk = ambientSensorOk; }
    public void setFanVerified(Boolean fanVerified) { this.fanVerified = fanVerified; }
    public String getClassification() { return classification; }
    public void setClassification(String classification) { this.classification = classification; }
    public Integer getHealthScore() { return healthScore; }
    public void setHealthScore(Integer healthScore) { this.healthScore = healthScore; }
    public Boolean getBuffered() { return buffered; }
    public void setBuffered(Boolean buffered) { this.buffered = buffered; }
    public Long getBufferedAgoMs() { return bufferedAgoMs; }
    public void setBufferedAgoMs(Long bufferedAgoMs) { this.bufferedAgoMs = bufferedAgoMs; }
    public String getIncidentReport() { return incidentReport; }
    public void setIncidentReport(String incidentReport) { this.incidentReport = incidentReport; }
    public String getReportProvider() { return reportProvider; }
    public void setReportProvider(String reportProvider) { this.reportProvider = reportProvider; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt == null ? Instant.now() : createdAt; }
}
