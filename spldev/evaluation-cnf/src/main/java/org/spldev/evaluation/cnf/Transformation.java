package org.spldev.evaluation.cnf;

import de.ovgu.featureide.fm.core.analysis.cnf.CNF;
import de.ovgu.featureide.fm.core.analysis.cnf.formula.FeatureModelFormula;
import de.ovgu.featureide.fm.core.base.IFeatureModel;
import de.ovgu.featureide.fm.core.io.dimacs.DIMACSFormatCNF;
import de.ovgu.featureide.fm.core.io.manager.FeatureModelManager;
import org.sosy_lab.common.ShutdownManager;
import org.sosy_lab.common.configuration.Configuration;
import org.sosy_lab.common.configuration.InvalidConfigurationException;
import org.sosy_lab.common.log.BasicLogManager;
import org.sosy_lab.common.log.LogManager;
import org.sosy_lab.java_smt.SolverContextFactory;
import org.sosy_lab.java_smt.api.*;
import org.spldev.evaluation.util.ModelReader;
import org.spldev.formula.expression.Formula;
import org.spldev.formula.expression.atomic.Atomic;
import org.spldev.formula.expression.atomic.literal.VariableMap;
import org.spldev.formula.expression.io.DIMACSFormat;
import org.spldev.formula.expression.io.FormulaFormatManager;
import org.spldev.formula.expression.transform.Transformer;
import org.spldev.formula.solver.RuntimeTimeoutException;
import org.spldev.formula.solver.javasmt.FormulaToJavaSmt;
import org.spldev.util.data.Pair;
import org.spldev.util.io.FileHandler;
import org.spldev.util.job.Executor;
import org.spldev.util.logging.Logger;
import org.spldev.util.tree.Trees;
import org.spldev.util.tree.structure.Tree;
import org.spldev.util.tree.visitor.TreeVisitor;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.List;
import java.util.concurrent.*;

public abstract class Transformation implements Serializable {
	private static final long serialVersionUID = 1L;
	public static Transformation[] transformations = new Transformation[] {
		new Z3(),
		new FeatureIDE(),
	};

	public Parameters parameters;

	public void setParameters(Parameters parameters) {
		this.parameters = parameters;
		this.parameters.transformation = this;
	}

	static class Result<T> extends Pair<Long, T> {
		public Result(Long key, T value) {
			super(key, value);
		}
	}

	public static Transformation read(Path path) {
		try {
			FileInputStream fileInputStream = new FileInputStream(path.toFile());
			ObjectInputStream objectInputStream = new ObjectInputStream(fileInputStream);
			Transformation transformation = (Transformation) objectInputStream.readObject();
			objectInputStream.close();
			return transformation;
		} catch (IOException | ClassNotFoundException e) {
			e.printStackTrace();
		}
		return null;
	}

	public void write(Path path) {
		try {
			FileOutputStream fileOutputStream = new FileOutputStream(path.toFile());
			ObjectOutputStream objectOutputStream = new ObjectOutputStream(fileOutputStream);
			objectOutputStream.writeObject(this);
			objectOutputStream.flush();
			objectOutputStream.close();
		} catch (IOException e) {
			e.printStackTrace();
		}
	}

	@Override
	public String toString() {
		return getClass().getSimpleName() + "{" +
			"parameters=" + parameters +
			'}';
	}

	protected <T> Result execute(Callable<T> method) {
		final ExecutorService executor = Executors.newSingleThreadExecutor();
		final Future<Result> future = executor.submit(() -> {
			T payload = null;
			final long localTime = System.nanoTime();
			try {
				payload = method.call();
			} catch (Exception e) {
				e.printStackTrace();
			}
			final long timeNeeded = System.nanoTime() - localTime;
			return payload == null ? null : new Result(timeNeeded, payload);
		});
		try {
			return future.get(parameters.timeout, TimeUnit.MILLISECONDS);
		} catch (TimeoutException | ExecutionException | InterruptedException | RuntimeTimeoutException e) {
			System.exit(0);
		} finally {
			executor.shutdownNow();
		}
		return null;
	}

	protected Path getTempPath(String suffix) {
		return Paths.get(parameters.tempPath).resolve(
			String.format("%s_%s_%d.%s",
				parameters.system.replaceAll("[/]", "_"),
				parameters.transformation, parameters.iteration, suffix));
	}

	protected Path getTempPath() {
		return getTempPath("dimacs");
	}

	abstract public void run() throws Exception;

	public static class LiteralsCounter implements TreeVisitor<Integer, Tree<?>> {

		private int literals = 0;

		@Override
		public void reset() {
			literals = 0;
		}

		@Override
		public VisitorResult firstVisit(List<Tree<?>> path) {
			if (TreeVisitor.getCurrentNode(path) instanceof Atomic)
				literals++;
			return VisitorResult.Continue;
		}

		@Override
		public Integer getResult() {
			return literals;
		}
	}

	public static class Z3 extends Transformation {
		@Override
		public void run() throws IOException, InvalidConfigurationException {
			final ModelReader<Formula> fmReader = new ModelReader<>();
			fmReader.setPathToFiles(Paths.get(parameters.rootPath));
			fmReader.setFormatSupplier(FormulaFormatManager.getInstance());
			Formula formula = fmReader.read(Paths.get(parameters.modelPath).toString())
					.orElseThrow(p -> new RuntimeException("no feature model"));
			VariableMap variableMap = VariableMap.fromExpression(formula);

			Configuration config = Configuration.defaultConfiguration();
			LogManager logManager = BasicLogManager.create(config);
			ShutdownManager shutdownManager = ShutdownManager.create();
			SolverContext context = SolverContextFactory.createSolverContext(config, logManager, shutdownManager
					.getNotifier(), SolverContextFactory.Solvers.Z3);
			FormulaManager formulaManager = context.getFormulaManager();
			BooleanFormula input = new FormulaToJavaSmt(context, variableMap).nodeToFormula(formula);

			Files.write(Paths.get(getTempPath("smt").toString()),
					formulaManager.dumpFormula(input).toString().getBytes());
		}

		@Override
		public String toString() {
			return "z3";
		}
	}

	public static class FeatureIDE extends Transformation {
		@Override
		public void run() {
			// todo: use FeatureIDE 3.5.5
			final IFeatureModel featureModel = FeatureModelManager
					.load(Paths.get(parameters.rootPath).resolve(parameters.modelPath));
			if (featureModel != null) {
				Result<CNF> result = execute(() -> new FeatureModelFormula(featureModel).getCNF());
				if (result != null) {
					de.ovgu.featureide.fm.core.io.manager.FileHandler.save(getTempPath(), result.getValue(),
							new DIMACSFormatCNF());
					try {
						Files.write(getTempPath(), ("c time " + result.getKey()).getBytes(), StandardOpenOption.APPEND);
					} catch (IOException e) {
					}
				}
			}
		}

		@Override
		public String toString() {
			return "featureide";
		}
	}

	public static class KConfigReader extends Transformation {
		@Override
		public void run() {
			// todo: export kcr model format for input to kconfigreader-cnftransform (even for stage 1!)
		}

		@Override
		public String toString() {
			return "kconfigreader";
		}
	}
}