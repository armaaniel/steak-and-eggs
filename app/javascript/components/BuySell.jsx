import React, { useState } from "react";

const BuySell = () => {
  const [currentState, setCurrentState] = useState({ action: "buy", step: 1 });

  const nextStep = () =>
    setCurrentState({ ...currentState, step: currentState.step + 1 });
  const prevStep = () =>
    setCurrentState({ ...currentState, step: currentState.step - 1 });
  const buyState = () => setCurrentState({ action: "buy", step: 1 });
  const sellState = () => setCurrentState({ action: "sell", step: 1 });

  return (
    <>
      {currentState.action === "buy" && currentState.step === 1 && (
        <div>
          <div>
            <button onClick={buyState}>Buy</button>
            <button onClick={sellState}>Sell</button>
          </div>
          <label>Shares</label>
          <form>
            <input type="number" placeholder="0" name="quantity" min="1" step="1"/>
          </form>
          <p>Estimated Cost</p>
          <p>Available Cash</p>
          <button onClick={nextStep}>Next</button>
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 1 && (
        <div>
          <div>
            <button onClick={buyState}>Buy</button>
            <button onClick={sellState}>Sell</button>
          </div>
          <label>Shares</label>
          <form>
            <input type="number" placeholder="0" name="quantity" min="1" step="1"/>
          </form>
          <p>Estimated Value</p>
          <p>Available Shares</p>
          <button onClick={nextStep}>Next</button>
        </div>
      )}

      {currentState.action === "buy" && currentState.step === 2 && (
        <div>
          <button onClick={prevStep}>back</button>
          <p> order type</p>
          <p> quantity </p>
          <p> cost </p>
          <button onClick={nextStep}>Submit Order</button>
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 2 && (
        <div>
          <button onClick={prevStep}>back</button>
          <p> order type</p>
          <p> quantity </p>
          <p> cost </p>
          <button onClick={nextStep}>Submit Order</button>
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 3 && (
        <div>
          <h2>Order Submitted!</h2>
          <p> Submitted</p>
          <p> order type</p>
          <p> Shares </p>
          <p> Value</p>
          <button onClick={buyState}>Done</button>
        </div>
      )}

      {currentState.action === "buy" && currentState.step === 3 && (
        <div>
          <h2>Order Submitted!</h2>
          <p> Submitted</p>
          <p> order type</p>
          <p> Shares </p>
          <p> Cost</p>
          <button onClick={buyState}>Done</button>
        </div>
      )}
    </>
  );
};

export default BuySell;
