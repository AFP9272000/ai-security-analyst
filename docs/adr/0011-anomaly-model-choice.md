# ADR 0011: IsolationForest for Anomaly Detection

## Context

The platform needs an anomaly detection model that scores CloudTrail
events for unusualness. Three families of candidate models:

**Classical unsupervised:** IsolationForest, One-Class SVM, Local
Outlier Factor (LOF), Elliptic Envelope. All sklearn-native.

**Deep unsupervised:** Autoencoders, Variational Autoencoders.
PyTorch or TensorFlow.

**Sequence models:** LSTMs or Transformers trained on user-session
sequences. PyTorch.

## Decision

**IsolationForest** for the v1 production model.

## Rationale

**Interpretability is critical for security tooling.** Output scores
from IsolationForest map intuitively to "how isolated is this point
from the rest of the data" - a concept analysts already think in. The
contamination hyperparameter directly controls the false-positive rate.
Autoencoders output reconstruction error, which is more abstract;
explaining a specific finding's score to a non-ML user is harder.

**Real SOC tools use this family.** AWS Macie's early anomaly detection,
Datadog Cloud SIEM's behavioral analytics, and Splunk's MLTK anomaly
detection all use IsolationForest or close variants. Choosing the
canonical model lets the portfolio piece land on familiar ground in
interviews.

**Training and inference are orders of magnitude cheaper.** IsolationForest
trains in seconds on millions of rows, inference is ~1ms per request,
and the model serializes to a few MB. A comparable autoencoder takes
minutes/hours to train, inference is 10-50ms (compute graph overhead),
and the model is 100MB+.

**The model is hyperparameter-friendly.** Tuning contamination,
n_estimators, max_samples covers most production needs. Hyperparameter
search is fast enough to do in CI. Deep models would need GPU instances
for tuning runs.

**Failure modes are well-documented.** When IsolationForest produces
bad outputs, the cause is usually one of three known issues:
contamination set too high, training data too small, or feature
distributions too uniform. Each has a documented fix. Deep models
fail in more varied ways (catastrophic forgetting, mode collapse,
gradient issues), and debugging those requires deeper expertise.

## What we lose

**Sequence modeling.** IsolationForest treats each event independently.
A model that scored sequences could catch attacks that unfold over
multiple events (e.g. enumerate-then-exfiltrate patterns). The trade
is acceptable for v1; the enricher Lambda's `raw_detail` field
preserves the full event context for downstream sequence analysis in
later iterations.

**Modern AI signaling.** "Built an autoencoder for anomaly detection"
sounds more impressive on a resume than "built an IsolationForest."
That's a real consideration for a portfolio project, but the
practical benefits of IsolationForest are large enough that picking
the right tool is itself the signal.

## Consequences

**Positive:**

- Fast training (seconds), low inference latency (ms)
- Tiny model artifact (<10 MB)
- Cheap SageMaker instances (`ml.m5.large` for training, `ml.t2.medium`
  for inference)
- Interpretable outputs
- Failure modes well-understood

**Negative:**

- No sequence/temporal modeling without additional engineering
- Less impressive on a "what model did you use" surface read
- Limited ability to capture high-dimensional non-linear patterns

**Mitigated:**

- Future iterations can add a deep model as a *second* scorer that
  feeds into the same enriched-findings pipeline. The architecture
  doesn't lock in a single model
- The portfolio narrative emphasizes architecture decisions
  (multi-account, IaC, Bedrock agent) more than model exotica
