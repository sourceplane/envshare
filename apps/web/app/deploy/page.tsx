"use client";
import { ArrowTopRightOnSquareIcon } from "@heroicons/react/20/solid";
import Link from "next/link";
import { Title } from "@components/title";
import { SITE_NAME, SOURCE_URL } from "lib/site";
import React from "react";
const steps: {
  name: string;
  description: string | React.ReactNode;
  cta?: React.ReactNode;
}[] = [
  {
    name: "Get the source",
    description: (
      <>
        {SITE_NAME} is open source. Fork its repository: everything it runs on is described there, from the
        Cloudflare resources to the pipeline that deploys them.
      </>
    ),
    cta: (
      <Link
        href={SOURCE_URL}
        className="flex items-center justify-center w-full gap-2 px-4 py-2 text-sm text-center transition-all duration-150 rounded text-zinc-800 hover:text-zinc-100 bg-zinc-200 hover:bg-transparent ring-1 ring-zinc-100"
      >
        <span>View the source</span>
        <ArrowTopRightOnSquareIcon className="w-4 h-4" />
      </Link>
    ),
  },
  {
    name: "Create a Cloudflare account",
    description: (
      <p>
        It runs on Cloudflare Workers, with the encrypted documents in Workers KV and their read limits in D1 —
        all within Cloudflare&apos;s free plan.
      </p>
    ),
    cta: (
      <Link
        href="https://dash.cloudflare.com/sign-up"
        className="flex items-center justify-center w-full gap-2 px-4 py-2 text-sm text-center transition-all duration-150 rounded text-zinc-800 hover:text-zinc-100 bg-zinc-200 hover:bg-transparent ring-1 ring-zinc-100"
      >
        <span>Sign up</span>
        <ArrowTopRightOnSquareIcon className="w-4 h-4" />
      </Link>
    ),
  },
  {
    name: "Deploy",
    description:
      "The repository's README says how its pipeline provisions the namespace and the database and deploys the site to stage and prod.",
    cta: (
      <Link
        href={`${SOURCE_URL}#readme`}
        className="flex items-center justify-center w-full gap-2 px-4 py-2 text-sm text-center transition-all duration-150 rounded text-zinc-800 hover:text-zinc-100 bg-zinc-200 hover:bg-transparent ring-1 ring-zinc-100"
      >
        <span>Read the README</span>
        <ArrowTopRightOnSquareIcon className="w-4 h-4" />
      </Link>
    ),
  },
];

export default function Deploy() {
  return (
    <div className="container px-8 mx-auto mt-16 lg:mt-32 ">
      <Title>Deploy {SITE_NAME} for Free</Title>
      <p className="mt-4 text-sm text-center text-zinc-600">
        You can deploy your own hosted version of {SITE_NAME}; you just need a Cloudflare account.
      </p>
      <ol className="flex flex-col items-center justify-center mt-8 md:mt-16 xl:mt-24">
        {steps.map((step, stepIdx) => (
          <li key={step.name} className="relative flex flex-col items-center gap-4 pb-16 group md:gap-8 md:pb-24">
            <span
              className="absolute top-4  h-full w-0.5 bg-gradient-to-b from-blue-500/60  via-blue-500/10 to-transparent"
              aria-hidden="true"
            />
            <span className="flex items-center h-9" aria-hidden="true">
              <span className="relative z-10 flex items-center justify-center w-8 h-8 text-sm text-blue-400 duration-150 border border-blue-400 rounded-full bg-zinc-900 group-hover:border-blue-500 drop-shadow-blue">
                {stepIdx + 1}
              </span>
            </span>
            <div className="z-10 flex flex-col items-center">
              <h2 className="text-xl font-medium duration-150 lg:text-2xl text-zinc-200 group-hover:text-white">
                {step.name}
              </h2>

              <div className="mt-4 text-sm text-center duration-1000 text-zinc-500 group-hover:text-zinc-400">
                {step.description}
              </div>
              <div className="w-full mt-8 md:w-auto">{step.cta}</div>
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}
