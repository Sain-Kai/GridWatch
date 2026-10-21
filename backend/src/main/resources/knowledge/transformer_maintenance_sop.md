# GridWatch Distribution Transformer Monitoring Guideline (Demo SOP)

This is a short, original reference document written for the GridWatch
course project. It is not an official utility standard - it exists so
the RAG layer has real text to ground its answers in, instead of the
LLM inventing procedures from nothing.

## Section 1: Temperature Thresholds

Normal operating casing temperature for a small distribution
transformer under this monitoring profile is below 55C. A sustained
reading above 55C should be treated as an overheating event. A rapid
rise of more than 1.5C per second is a stronger early-warning signal
than the absolute temperature alone, since it can indicate an active
fault (such as a short-circuited winding) rather than slow ambient
heating from sun or load. Any overheating event should trigger an
immediate visual inspection and, if the temperature continues to
climb after 5 minutes, a request for a maintenance crew dispatch.

## Section 2: Panel Access and Tamper Events

The monitoring panel door is fitted with a break-beam sensor. A beam
break while the site is not in a scheduled maintenance window should
be logged as a possible intrusion or theft attempt (oil theft and
copper theft are common causes of unscheduled panel access). A sudden
spike on the door-pressure sensor without a corresponding scheduled
maintenance ticket should be treated the same way. The recommended
first response is a remote camera or site-guard check before
dispatching a technician, to avoid unnecessary site visits.

## Section 3: Sensor Fault Handling

A thermocouple reading below -10C or above 250C on this hardware
almost always indicates a disconnected or damaged probe rather than a
real temperature, since distribution transformers do not legitimately
operate outside that range. This should be logged as a sensor fault,
not an overheating event, and scheduled for probe replacement at the
next routine visit rather than an emergency dispatch.

## Section 3b: Cooling-Fan Verification (COOLING_FAILURE vs THERMAL_WARNING)

When the monitoring node detects a temperature deviation above the
expected value for the current ambient temperature and load, it does
not raise an alarm from the temperature reading alone. It actively
commands the cooling fan on and checks, using a rotation sensor, that
the fan actually spun up. If the fan is confirmed spinning and the
temperature is still elevated, this should be logged as THERMAL_WARNING
(likely an overload condition - the cooling system is working but is
not enough on its own) and scheduled for a routine load-review visit.
If the fan does NOT spin up when commanded, this should be logged as
COOLING_FAILURE and escalated for same-day inspection, since a
non-responsive cooling fan under rising load is a near-term fire risk.

## Section 3c: Buffered / Delayed Events

A node may lose its network link during a power outage and continue
to log locally rather than losing the data. When a delayed reading
arrives tagged as buffered, treat its timestamp as the time it was
actually captured, not the time it arrived. A buffered COOLING_FAILURE
or CRITICAL_OVERHEAT event should still be escalated for inspection
even though it is historical, since the underlying fault may still be
present; a buffered NORMAL or THERMAL_WARNING event is informational
only and does not need a fresh dispatch.

## Section 4: General Response Priority

When multiple conditions are flagged at once, prioritize overheating
events first (fire/equipment-damage risk), then intrusion/tamper
events (safety and theft risk), then sensor faults (data-quality
issue, lowest urgency). Battery-backed nodes should continue logging
through a mains outage; a gap in logged data during a known outage
window is expected and should not itself be treated as a fault.
